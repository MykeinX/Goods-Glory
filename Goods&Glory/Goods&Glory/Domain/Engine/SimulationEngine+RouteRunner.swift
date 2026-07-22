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

    /// Distant sentinel for waits with no timer (cargo not due yet).
    static let waitSentinel = GameTime(totalMinutes: Int.max / 4)
    /// Retry delay when a lap makes no progress or a leg has no road.
    static let idleRetryMinutes = 60

    /// Spawns runs for idle vehicles on running routes and re-evaluates
    /// sentinel waits. Called from the event loop and route commands.
    func syncRouteRuns(state: inout GameState) {
        // `isVehicleIdle` rescans activeJobs and routeRuns, so calling it per
        // assigned vehicle made this O(fleet × (jobs + runs)) on every pass of
        // the advance loop. The busy set is computed once and updated as runs
        // are spawned, which keeps the same "already busy" semantics.
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
        func skip(loggingJob jobID: JobID? = nil) {
            if let jobID {
                state.appendLog(.routeShipmentSkipped(routeID: route.id, jobID: jobID))
            }
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

        case .pickupShipment(let jobID):
            let claimedByAnotherRun = state.routeRuns.contains {
                $0.id != runID && $0.claimedShipmentIDs.contains(jobID)
            }
            guard !run.isWindingDown,
                  let shipment = state.shipment(jobID),
                  shipment.loadedVehicleID == nil,
                  !claimedByAnotherRun else {
                skip()
                return
            }
            // The parcel may be at its origin address or resting in this
            // city's warehouse after an earlier leg — both are collectable.
            let isHere = shipment.location == .address(stop.cityID)
                || state.warehouseSite(in: stop.cityID).map { shipment.location == .warehouse($0.id) } == true
            guard isHere else {
                skip(loggingJob: jobID)
                return
            }
            guard combinedLoad(state.cargoLoad(of: vehicle.id), shipment.offer.load)
                .fits(in: vehicleType.capacity) else {
                skip(loggingJob: jobID)
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: true,
                    massKg: shipment.offer.load.massKg,
                    at: stop.cityID,
                    state: state
                ),
                claiming: [jobID]
            )

        case .pickupContract(let contractID):
            guard !run.isWindingDown, state.activeContract(contractID) != nil else {
                skip()
                return
            }
            // Fill the vehicle, do not take one parcel and drive off. Loading a
            // single parcel into a semi meant three quarters of every trip was
            // paid for and empty — the surest way to lose money on a contract.
            // Filling here is also what makes a bigger truck, or one truck
            // serving two contracts at the same dock, actually pay off.
            let pending = state.offers
                .filter { $0.source == .contract && $0.contractID == contractID && $0.origin == stop.cityID }
                .sorted { ($0.expiresAt, $0.id.rawValue) < ($1.expiresAt, $1.id.rawValue) }
            guard !pending.isEmpty else {
                waitForCargo()
                return
            }
            var running = state.cargoLoad(of: vehicle.id)
            var claimed: [JobID] = []
            for offer in pending {
                let combined = combinedLoad(running, offer.load)
                guard combined.fits(in: vehicleType.capacity) else { continue }
                running = combined
                claimed.append(offer.id)
            }
            guard !claimed.isEmpty else {
                // Already full from an earlier stop: come back next lap.
                skip(loggingJob: pending[0].id)
                return
            }
            // Claim now so the obligations cannot expire mid-loading.
            let claimedSet = Set(claimed)
            for offer in pending where claimedSet.contains(offer.id) {
                state.shipments.append(Shipment(
                    id: offer.id,
                    offer: offer,
                    location: .address(offer.origin),
                    assignedRouteID: route.id
                ))
            }
            state.offers.removeAll { claimedSet.contains($0.id) }
            startService(
                minutes: handlingMinutes(
                    loading: true,
                    massKg: shipmentMass(of: claimed, state: state),
                    at: stop.cityID,
                    state: state
                ),
                claiming: claimed
            )

        case .pickupLane(let laneID):
            guard !run.isWindingDown, let lane = catalog.lane(laneID),
                  lane.originCityID == stop.cityID else {
                skip()
                return
            }
            // Committed freight first. A contract is a reserved share of this
            // very lane, so a route already serving the lane is exactly what
            // should be carrying it — requiring a separate `pickupContract`
            // stop for the same dock was the reason signing a contract for
            // freight you already hauled made the board report it uncovered.
            let committed = claimCommittedParcels(
                laneID: laneID,
                at: stop.cityID,
                vehicle: vehicle,
                vehicleType: vehicleType,
                routeID: route.id,
                state: &state
            )
            // Then whatever else is waiting, up to remaining capacity — but not
            // the room the route still owes to committed freight.
            //
            // A route serving several lanes out of one city visits them stop by
            // stop. Topping the truck up with spot at the first stop filled it
            // to 100%, and a commitment waiting at the next stop could then
            // never fit: one contract on this lane was posted, penalised and
            // re-posted for a week without a single parcel ever being lifted.
            // Reserving the room first is what makes an SLA an SLA.
            let stillOwed = committedRoomStillNeeded(
                route: route,
                at: stop.cityID,
                excluding: Set(committed),
                capacity: vehicleType.capacity,
                state: state
            )
            // If a commitment is still standing on this dock unlifted, this
            // truck takes no spot freight at all.
            //
            // Reserving *room* was not enough. A small commitment that cannot
            // fit beside a big one is passed over lap after lap, and each lap
            // the truck fills the gap with spot — so the room never appears and
            // the parcel ages out, every cycle, penalty included. Refusing spot
            // while anything is owed here means the next truck arrives empty
            // enough to take it. Spot freight is always replaceable; a
            // commitment has a deadline and a fine attached.
            let owesMore = stillOwed.massKg > 0
            let claimed = committed + (owesMore ? [] : claimLaneParcels(
                lane: lane,
                vehicle: vehicle,
                vehicleType: vehicleType,
                routeID: route.id,
                reservedLoad: shipmentLoad(of: committed, state: state),
                state: &state
            ))
            // Logged only when the truck leaves this stop with nothing: that is
            // the case a reader needs explained. When it did take the committed
            // parcel the `SLA` line already says so, and one line per lane stop
            // buried the log in five identical entries.
            // One line per city visit, not per lane stop. A route working six
            // lanes out of one dock wrote six identical entries in the same
            // minute, which buried everything around them.
            if owesMore, committed.isEmpty, run.lastHoldNotedAt != state.clock {
                state.recordDebug(
                    .running,
                    "HOLD  r\(route.id.rawValue) v\(vehicle.id.rawValue) \(short(stop.cityID)) "
                        + "took no spot: \(kg(stillOwed.massKg)) of committed freight waits for room"
                )
                run.lastHoldNotedAt = state.clock
                if let index = state.routeRuns.firstIndex(where: { $0.id == run.id }) {
                    state.routeRuns[index].lastHoldNotedAt = state.clock
                }
            }
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

        case .deliverShipment(let jobID):
            guard let shipment = state.shipment(jobID),
                  shipment.loadedVehicleID == vehicle.id else {
                skip()
                return
            }
            guard shipment.isDeliverable(at: stop.cityID) else {
                skip(loggingJob: jobID)
                return
            }
            startService(
                minutes: handlingMinutes(
                    loading: false,
                    massKg: shipment.offer.load.massKg,
                    at: stop.cityID,
                    state: state
                ),
                claiming: [jobID]
            )

        case .deliverContract(let contractID):
            let deliverable = state.shipments.filter {
                $0.loadedVehicleID == vehicle.id
                    && $0.offer.contractID == contractID
                    && $0.offer.destination == stop.cityID
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
                let stuck = state.shipments
                    .filter { $0.loadedVehicleID == run.vehicleID }
                    .sorted { $0.id.rawValue < $1.id.rawValue }
                state.shipments.removeAll { $0.loadedVehicleID == run.vehicleID }
                for shipment in stuck { detachShipment(shipment, state: &state) }
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

    /// Flags routes that still carry stops for an ended contract. No route is
    /// ever closed for losing a contract: the lane keeps running, its lane
    /// stops keep earning at the spot rate (the base the contract sat on),
    /// and the falling utilisation is the player's signal to edit or fold it.
    /// The flag exists because silently skipped stops are how a player ends
    /// up paying for laps that collect less than they could.
}
