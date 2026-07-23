//
//  SimulationEngine+RouteRunner.swift
//  Goods&Glory
//
//  Execution: how a vehicle walks a route — travel, service, waiting,
//  loading, delivery settlement and wind-down.
//

import Foundation

extension SimulationEngine {
    // MARK: - Route runner

    /// Distant sentinel for warehouse waits with no timer.
    static let waitSentinel = GameTime(totalMinutes: Int.max / 4)
    /// Retry delay when a lap makes no progress or a leg has no road.
    static let idleRetryMinutes = 60

    /// Spawns runs for idle vehicles on running routes and re-evaluates
    /// sentinel waits. Called from the event loop and route commands.
    func syncRouteRuns(state: inout GameState) {
        // The busy set is computed once and updated as runs are spawned, so the
        // advance loop never rescans all runs once per assigned vehicle.
        var busy = state.busyVehicleIDs()
        for route in state.routes where route.isRunning && !route.stops.isEmpty {
            for vehicleID in route.vehicleIDs where !busy.contains(vehicleID) {
                // Routes covering a lane: do not send another truck while active runs still
                // have room for everything waiting at the dock. That is what
                // turned "7t needs capacity" + a second vehicle into empty laps.
                if shouldHoldExtraVehicle(route: route, state: state) { continue }
                let runsBefore = state.routeRuns.count
                spawnRun(routeID: route.id, vehicleID: vehicleID, state: &state)
                // Only a run that was actually created makes the vehicle busy —
                // `spawnRun` bails on dangling references, and the old code
                // would have re-tried such a vehicle on the next route.
                if state.routeRuns.count != runsBefore { busy.insert(vehicleID) }
            }
        }
        let sentinelWaiters = state.routeRuns
            .filter {
                $0.phase == .waiting
                    && ($0.phaseEndsAt == Self.waitSentinel || $0.isWindingDown)
            }
            .map(\.id)
            .sorted()
        for runID in sentinelWaiters {
            beginService(runID: runID, state: &state)
        }
        finalizeCancelledRoutes(state: &state)
    }

    func spawnRun(routeID: RouteID, vehicleID: VehicleID, state: inout GameState) {
        guard let route = state.route(routeID), !route.stops.isEmpty,
              let vehicle = state.vehicle(vehicleID),
              let vehicleType = catalog.vehicleType(vehicle.typeID) else { return }
        var run = RouteRun(
            id: state.issueID(),
            routeID: routeID,
            vehicleID: vehicleID,
            stopIndex: 0,
            phase: .traveling,
            phaseStartedAt: state.clock,
            phaseEndsAt: state.clock,
            legOriginCityID: vehicle.cityID,
            legDistanceKm: 0,
            lapStartedAt: state.clock,
            claimedShipmentIDs: [],
            isWindingDown: false
        )
        applyLeg(
            &run,
            from: vehicle.cityID,
            to: route.stops[0].cityID,
            vehicleType: vehicleType,
            clock: state.clock,
            worldSeed: state.config.seed
        )
        state.routeRuns.append(run)
    }

    /// Routes covering a lane only: hold idle extras while every kilogram waiting at the
    /// covered docks still fits in the free capacity of runs already out.
    /// Sending them anyway is how a second truck racks up empty kilometres.
    func shouldHoldExtraVehicle(route: Route, state: GameState) -> Bool {
        guard !route.coveredLaneIDs.isEmpty else { return false }
        let active = state.routeRuns(of: route.id)
        guard !active.isEmpty else { return false }

        let waiting = route.coveredLaneIDs.reduce(0) { $0 + (state.laneAccrualKg[$1] ?? 0) }
        let freeCapacity = active.reduce(0) { total, run in
            guard let vehicle = state.vehicle(run.vehicleID),
                  let type = catalog.vehicleType(vehicle.typeID) else { return total }
            let used = state.cargoLoad(of: vehicle.id).massKg
                + run.claimedShipmentIDs.reduce(0) {
                    $0 + (state.shipment($1)?.offer.load.massKg ?? 0)
                }
            return total + max(0, type.capacity.massKg - used)
        }
        return waiting <= freeCapacity
    }

    /// Fills traveling-phase fields for a leg; falls back to a timed wait when
    /// the road network offers no path. Live travel gets seeded ±15% variance.
    func applyLeg(
        _ run: inout RouteRun,
        from origin: CityID,
        to destination: CityID,
        vehicleType: VehicleTypeDefinition,
        clock: GameTime,
        worldSeed: UInt64
    ) {
        run.phaseStartedAt = clock
        run.legOriginCityID = origin
        if origin == destination {
            run.phase = .traveling
            run.legDistanceKm = 0
            run.phaseEndsAt = clock
        } else if let leg = catalog.shortestRoute(from: origin, to: destination) {
            run.phase = .traveling
            run.legDistanceKm = leg.distanceKm
            let base = travelMinutes(distanceKm: leg.distanceKm, speedKmh: vehicleType.speedKmh)
            let minutes = variedDurationMinutes(
                base: base,
                worldSeed: worldSeed,
                kind: "route_leg",
                vehicleID: run.vehicleID,
                eventID: run.id ^ (run.stopIndex &* 1_000_003),
                at: clock
            )
            run.phaseEndsAt = clock + minutes
        } else {
            run.phase = .waiting
            run.legDistanceKm = 0
            run.phaseEndsAt = clock + Self.idleRetryMinutes
        }
    }

    func advanceRouteRun(id: Int, state: inout GameState) {
        guard let runIndex = state.routeRuns.firstIndex(where: { $0.id == id }) else { return }
        var run = state.routeRuns[runIndex]
        guard let route = state.route(run.routeID), !route.stops.isEmpty,
              let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == run.vehicleID }),
              let vehicleType = catalog.vehicleType(state.vehicles[vehicleIndex].typeID) else {
            state.routeRuns.remove(at: runIndex)
            return
        }
        if !route.stops.indices.contains(run.stopIndex) {
            run.stopIndex = 0
        }

        switch run.phase {
        case .traveling:
            // Arrival: position, mileage and the leg's operating cost settle here.
            let stop = route.stops[run.stopIndex]
            state.vehicles[vehicleIndex].cityID = stop.cityID
            state.vehicles[vehicleIndex].odometerKm += run.legDistanceKm
            if run.legDistanceKm > 0 {
                let minutes = run.phaseStartedAt.minutes(until: run.phaseEndsAt)
                let cost = taskCost(totalKm: run.legDistanceKm, taskMinutes: minutes, vehicleType: vehicleType)
                state.cash -= cost
                state.stats.totalCost += cost
                // The route dashboard's raw material: every leg is either loaded
                // or the empty running the player is meant to engineer away.
                let load = state.cargoLoad(of: run.vehicleID)
                let carried = load.massKg > 0
                let fill = util(load: load, capacity: vehicleType.capacity)
                let clock = state.clock
                addRouteStats(route.id, state: &state) {
                    if carried {
                        $0.loadedKm += run.legDistanceKm
                    } else {
                        $0.emptyKm += run.legDistanceKm
                    }
                    $0.cost += cost
                    // Trailing efficiency: how full the truck was, not merely
                    // whether it carried something.
                    $0.noteWork(minutes: minutes, fill: fill, at: clock)
                }
                state.vehicles[vehicleIndex].load.note(minutes: minutes, fill: fill, at: clock)
                // The freight on board owes this leg; that debt is what the
                // route recovers if it hands the parcel over mid-journey.
                attributeCost(cost, toCargoOf: run.vehicleID, state: &state)
                // The single most important balancing line: what a leg costs
                // per km, and whether it carried anything while costing it.
                state.recordDebug(
                    .running,
                    delta: -cost,
                    "LEG   r\(route.id.rawValue) v\(run.vehicleID.rawValue) "
                        + "\(short(run.legOriginCityID))→\(short(stop.cityID)) "
                        + "\(km(run.legDistanceKm)) "
                        + (carried ? "load \(kg(load.massKg)) fill \(pct(fill))" : "EMPTY")
                        + " cost \(money(cost)) @\(rate(Double(cost) / max(1, run.legDistanceKm)))/km"
                )
            }
            state.routeRuns[runIndex] = run
            beginService(runID: id, state: &state)

        case .servicing:
            state.routeRuns[runIndex] = run
            completeService(runID: id, state: &state)

        case .waiting:
            // Timed wait expired: try the stop again.
            state.routeRuns[runIndex] = run
            beginService(runID: id, state: &state)
        }
    }

    /// Decides what happens at the run's current stop: start a service window,
    /// wait for cargo, or skip ahead. The vehicle is already in the stop's city.
    func beginService(runID: Int, state: inout GameState) {
        guard let runIndex = state.routeRuns.firstIndex(where: { $0.id == runID }) else { return }
        var run = state.routeRuns[runIndex]
        guard let route = state.route(run.routeID), route.stops.indices.contains(run.stopIndex),
              let vehicle = state.vehicle(run.vehicleID),
              let vehicleType = catalog.vehicleType(vehicle.typeID) else {
            state.routeRuns.remove(at: runIndex)
            return
        }
        let stop = route.stops[run.stopIndex]

        func startService(minutes: Int, claiming shipmentIDs: [JobID] = []) {
            let varied = variedDurationMinutes(
                base: minutes,
                worldSeed: state.config.seed,
                kind: "route_dock",
                vehicleID: run.vehicleID,
                eventID: run.id ^ (run.stopIndex &* 1_000_003),
                at: state.clock
            )
            run.phase = .servicing
            run.phaseStartedAt = state.clock
            run.phaseEndsAt = state.clock + varied
            run.claimedShipmentIDs = shipmentIDs
            state.routeRuns[runIndex] = run
        }
        func skip() {
            state.routeRuns[runIndex] = run
            advanceToNextStop(runID: runID, state: &state)
        }
        /// Nothing to load here yet.
        ///
        /// A vehicle with freight already on board never parks to wait for
        /// more: that cargo has a customer and a deadline, and holding it at a
        /// dock is how a lane silently racks up missed shipments. It moves on
        /// and delivers what it has. Only an empty vehicle waits, because for
        /// an empty vehicle waiting *is* the productive choice — driving an
        /// empty lap costs fuel and earns nothing.
        func waitForCargo() {
            guard state.cargoLoad(of: vehicle.id).massKg == 0 else {
                skip()
                return
            }
            run.phase = .waiting
            run.phaseStartedAt = state.clock
            run.phaseEndsAt = Self.waitSentinel
            run.claimedShipmentIDs = []
            state.routeRuns[runIndex] = run
        }

        switch stop.task {
        case .travel:
            skip()

        case .pickupLane(let laneID):
            guard !run.isWindingDown, let lane = catalog.lane(laneID),
                  lane.originCityID == stop.cityID else {
                skip()
                return
            }
            let claimed = claimLaneParcels(
                lane: lane,
                vehicle: vehicle,
                vehicleType: vehicleType,
                routeID: route.id,
                state: &state
            )
            guard !claimed.isEmpty else {
                // Nothing waiting (or no room left). Move on — parking for the
                // next accrual tick left trucks idle for hours; the next lap
                // collects what piles up meanwhile. Partial fills above already
                // load and leave, which is the intended behaviour.
                skip()
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: true,
                    massKg: shipmentMass(of: claimed, state: state),
                    at: stop.cityID,
                    state: state
                ),
                claiming: claimed
            )

        case .deliverAll:
            // One distribution run, many customers: everything that belongs
            // to this city comes off here.
            let deliverable = state.shipments.filter {
                $0.loadedVehicleID == vehicle.id && $0.isDeliverable(at: stop.cityID)
            }
            guard !deliverable.isEmpty else {
                skip()
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: false,
                    massKg: deliverable.reduce(0) { $0 + $1.offer.load.massKg },
                    at: stop.cityID,
                    state: state
                )
            )

        case .deliverLane(let laneID, let target):
            // The precise pairing for `pickupLane`: only this lane's cargo is
            // affected, so several products can be routed independently.
            let affected: [Shipment]
            switch target {
            case .destination:
                affected = state.shipments.filter {
                    $0.loadedVehicleID == vehicle.id
                        && $0.offer.laneID == laneID
                        && $0.isDeliverable(at: stop.cityID)
                }
            case .warehouse:
                guard state.warehouseSite(in: stop.cityID) != nil else {
                    skip()
                    return
                }
                affected = state.shipments.filter {
                    $0.loadedVehicleID == vehicle.id && $0.offer.laneID == laneID
                }
            }
            guard !affected.isEmpty else {
                skip()
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: false,
                    massKg: affected.reduce(0) { $0 + $1.offer.load.massKg },
                    at: stop.cityID,
                    state: state
                )
            )

        case .dropToWarehouse:
            guard state.warehouseSite(in: stop.cityID) != nil else {
                skip()
                return
            }
            // Cargo already at its final city is delivered, not warehoused.
            let storable = state.shipments.filter {
                $0.loadedVehicleID == vehicle.id && !$0.isDeliverable(at: stop.cityID)
            }
            guard !storable.isEmpty else {
                skip()
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: false,
                    massKg: storable.reduce(0) { $0 + $1.offer.load.massKg },
                    at: stop.cityID,
                    state: state
                )
            )

        case .loadFromWarehouse(let lotKey):
            guard !run.isWindingDown,
                  let warehouse = state.warehouseSite(in: stop.cityID) else {
                skip()
                return
            }
            let available = loadableFromWarehouse(
                facilityID: warehouse.id,
                lotKey: lotKey,
                vehicle: vehicle,
                vehicleType: vehicleType,
                state: state
            )
            guard !available.isEmpty else {
                // Nothing to take yet. A hub run parks rather than looping
                // empty; the sync pass wakes it when stock arrives.
                waitForCargo()
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: true,
                    massKg: shipmentMass(of: available, state: state),
                    at: stop.cityID,
                    state: state
                )
            )
        }
    }

    /// Handling duration at a city, shortened by a well-equipped warehouse.
    func advanceToNextStop(runID: Int, state: inout GameState) {
        guard let runIndex = state.routeRuns.firstIndex(where: { $0.id == runID }) else { return }
        var run = state.routeRuns[runIndex]
        guard let route = state.route(run.routeID), !route.stops.isEmpty,
              let vehicle = state.vehicle(run.vehicleID),
              let vehicleType = catalog.vehicleType(vehicle.typeID) else {
            state.routeRuns.remove(at: runIndex)
            return
        }

        // Wind-down completes once the vehicle carries nothing.
        if run.isWindingDown,
           state.shipments.allSatisfy({ $0.loadedVehicleID != vehicle.id }) {
            state.routeRuns.remove(at: runIndex)
            return
        }

        let next = (run.stopIndex + 1) % route.stops.count
        if next <= run.stopIndex {
            // A winding-down run that has completed a full lap still holding
            // cargo carries freight this route cannot deliver (e.g. a return
            // load with no delivery stop). Forfeit it and release the vehicle
            // so cancellation cannot loop forever.
            if run.isWindingDown {
                state.shipments.removeAll { $0.loadedVehicleID == run.vehicleID }
                state.routeRuns.remove(at: runIndex)
                return
            }
            // Lap wrapped. A lap that consumed no time can never make progress;
            // park the vehicle briefly instead of spinning.
            if run.lapStartedAt == state.clock {
                run.stopIndex = next
                run.phase = .waiting
                run.phaseStartedAt = state.clock
                run.phaseEndsAt = state.clock + Self.idleRetryMinutes
                run.claimedShipmentIDs = []
                state.routeRuns[runIndex] = run
                return
            }
            run.lapStartedAt = state.clock
        }
        run.stopIndex = next
        applyLeg(
            &run,
            from: vehicle.cityID,
            to: route.stops[next].cityID,
            vehicleType: vehicleType,
            clock: state.clock,
            worldSeed: state.config.seed
        )
        state.routeRuns[runIndex] = run
    }

    func combinedLoad(_ lhs: LoadSize, _ rhs: LoadSize) -> LoadSize {
        LoadSize(massKg: lhs.massKg + rhs.massKg, volumeM3: lhs.volumeM3 + rhs.volumeM3)
    }
}
