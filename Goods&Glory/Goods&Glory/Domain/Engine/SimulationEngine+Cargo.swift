//
//  SimulationEngine+Cargo.swift
//  Goods&Glory
//
//  What happens to freight at a stop: handling time, warehouse capacity,
//  loading, storing, collecting and settling a delivery.
//

import Foundation

extension SimulationEngine {
    func handlingMinutes(loading: Bool, massKg: Int = 0, at cityID: CityID, state: GameState) -> Int {
        let base = loading ? loadingMinutes(at: cityID) : unloadingMinutes(at: cityID)
        // Cargo handling on top of dock setup: each tonne costs a fifth of the
        // base dock time, so a full semi (~20 t) sits roughly 5× longer than an
        // empty handshake — long enough that a lane accrual tick can land
        // mid-load, and short loads still finish promptly.
        let cargo = Int((Double(max(0, massKg)) / 1000.0 * Double(base) / 5.0).rounded())
        let raw = base + cargo
        guard let facility = state.facility(in: cityID) else { return max(1, raw) }
        // Modules stack multiplicatively, and that is the whole point of the
        // module model: a warehouse alone stores well, docks alone turn trucks
        // fast, and a site with both does both. Two sites at the same total
        // investment can therefore be built for completely different jobs.
        var factor = 1.0
        for module in facility.modules {
            guard module.isOperational(at: state.clock),
                  let quote = quote(kind: module.kind, level: module.level, city: cityID) else { continue }
            factor *= quote.handlingFactor
        }
        return max(1, Int((Double(raw) * factor).rounded()))
    }

    /// Mass of a set of parcels — used to size dock time.
    func shipmentMass(of ids: [JobID], state: GameState) -> Int {
        ids.reduce(0) { total, id in
            total + (state.shipment(id)?.offer.load.massKg ?? 0)
        }
    }

    /// Parcels a vehicle can take from a warehouse lot right now: earliest
    /// deadline first, stopping when the vehicle is full.
    func loadableFromWarehouse(
        facilityID: FacilityID,
        lotKey: StorageLotKey,
        vehicle: Vehicle,
        vehicleType: VehicleTypeDefinition,
        state: GameState
    ) -> [JobID] {
        let candidates = state.shipments
            .filter {
                $0.location == .warehouse(facilityID)
                    && $0.lotKey == lotKey
                    && $0.loadedVehicleID == nil
            }
            .sorted { ($0.offer.expiresAt, $0.id.rawValue) < ($1.offer.expiresAt, $1.id.rawValue) }

        var running = state.cargoLoad(of: vehicle.id)
        var taken: [JobID] = []
        for shipment in candidates {
            let combined = combinedLoad(running, shipment.offer.load)
            guard combined.fits(in: vehicleType.capacity) else { continue }
            running = combined
            taken.append(shipment.id)
        }
        return taken
    }

    /// Remaining room in a warehouse.
    /// Everything the site can hold: the warehouse shell plus the shelving
    /// racked into it. Summed rather than read off the warehouse alone, so a
    /// module that adds storage does not have to be wired in at every call site.
    func storageCapacity(of facility: Facility, state: GameState) -> LoadSize {
        // No shell, no storage: racking on its own holds nothing, and a
        // warehouse still under construction holds nothing either.
        guard facility.operationalModule(.warehouse, at: state.clock) != nil else {
            return LoadSize(massKg: 0, volumeM3: 0)
        }
        var total = LoadSize(massKg: 0, volumeM3: 0)
        for module in facility.modules {
            guard module.isOperational(at: state.clock),
                  let quote = quote(kind: module.kind, level: module.level, city: facility.cityID)
            else { continue }
            total.massKg += quote.storage.massKg
            total.volumeM3 += quote.storage.volumeM3
        }
        return total
    }

    func freeStorage(of facility: Facility, state: GameState) -> LoadSize {
        let capacity = storageCapacity(of: facility, state: state)
        guard capacity.massKg > 0 || capacity.volumeM3 > 0 else {
            return LoadSize(massKg: 0, volumeM3: 0)
        }
        let used = state.storedLoad(in: facility.id)
        return LoadSize(
            massKg: max(0, capacity.massKg - used.massKg),
            volumeM3: max(0, capacity.volumeM3 - used.volumeM3)
        )
    }

    func completeService(runID: Int, state: inout GameState) {
        guard let runIndex = state.routeRuns.firstIndex(where: { $0.id == runID }) else { return }
        let run = state.routeRuns[runIndex]
        guard let route = state.route(run.routeID), route.stops.indices.contains(run.stopIndex),
              let vehicle = state.vehicle(run.vehicleID),
              let vehicleType = catalog.vehicleType(vehicle.typeID) else {
            state.routeRuns.remove(at: runIndex)
            return
        }
        let stop = route.stops[run.stopIndex]

        // Driver wages for the service window.
        let minutes = run.phaseStartedAt.minutes(until: run.phaseEndsAt)
        if minutes > 0 {
            let cost = taskCost(totalKm: 0, taskMinutes: minutes, vehicleType: vehicleType)
            state.cash -= cost
            state.stats.totalCost += cost
            // Dock time counts as worked time: a route that never leaves the
            // city is still working, and measuring only kilometres reported
            // nothing at all for it.
            let fill = util(load: state.cargoLoad(of: vehicle.id), capacity: vehicleType.capacity)
            let clock = state.clock
            addRouteStats(route.id, state: &state) {
                $0.cost += cost
                $0.noteWork(minutes: minutes, fill: fill, at: clock)
            }
            if let index = state.vehicles.firstIndex(where: { $0.id == vehicle.id }) {
                state.vehicles[index].load.note(minutes: minutes, fill: fill, at: clock)
            }
            attributeCost(cost, toCargoOf: vehicle.id, state: &state)
            state.recordDebug(
                .running,
                delta: -cost,
                "DOCK  r\(route.id.rawValue) v\(vehicle.id.rawValue) \(short(stop.cityID)) "
                    + "\(minutes)min wages \(money(cost))"
            )
        }

        switch stop.task {
        case .travel:
            break
        case .pickupLane(let laneID):
            // Freight that arrived while the docks were busy joins this load —
            // the longer, mass-scaled service window is what makes that possible.
            var toLoad = run.claimedShipmentIDs
            if !run.isWindingDown, let lane = catalog.lane(laneID) {
                let reserved = toLoad.reduce(LoadSize(massKg: 0, volumeM3: 0)) { running, jobID in
                    guard let shipment = state.shipment(jobID) else { return running }
                    return combinedLoad(running, shipment.offer.load)
                }
                let extra = claimLaneParcels(
                    lane: lane,
                    vehicle: vehicle,
                    vehicleType: vehicleType,
                    routeID: route.id,
                    reservedLoad: reserved,
                    state: &state
                )
                toLoad.append(contentsOf: extra)
            }
            for claimed in toLoad {
                guard let shipmentIndex = state.shipments.firstIndex(where: { $0.id == claimed })
                else { continue }
                state.shipments[shipmentIndex].location = .vehicle(vehicle.id)
                state.shipments[shipmentIndex].assignedRouteID = route.id
                let offer = state.shipments[shipmentIndex].offer
                state.appendLog(.jobPickedUp(jobID: claimed, origin: offer.origin, destination: offer.destination))
            }
        case .deliverAll:
            let deliverable = state.shipments
                .filter { $0.loadedVehicleID == vehicle.id && $0.isDeliverable(at: stop.cityID) }
                .map(\.id)
                .sorted { $0.rawValue < $1.rawValue }
            for jobID in deliverable {
                settleRouteDelivery(jobID: jobID, routeID: route.id, state: &state)
            }
        case .deliverLane(let laneID, let target):
            switch target {
            case .destination:
                let deliverable = state.shipments
                    .filter {
                        $0.loadedVehicleID == vehicle.id
                            && $0.offer.laneID == laneID
                            && $0.isDeliverable(at: stop.cityID)
                    }
                    .map(\.id)
                    .sorted { $0.rawValue < $1.rawValue }
                for jobID in deliverable {
                    settleRouteDelivery(jobID: jobID, routeID: route.id, state: &state)
                }
            case .warehouse:
                storeCarriedCargo(vehicleID: vehicle.id, cityID: stop.cityID, onlyLane: laneID, state: &state)
            }
        case .dropToWarehouse:
            storeCarriedCargo(vehicleID: vehicle.id, cityID: stop.cityID, state: &state)
        case .loadFromWarehouse(let lotKey):
            collectFromWarehouse(
                vehicleID: vehicle.id,
                cityID: stop.cityID,
                lotKey: lotKey,
                routeID: route.id,
                state: &state
            )
        }
        if let runIndex = state.routeRuns.firstIndex(where: { $0.id == runID }) {
            state.routeRuns[runIndex].claimedShipmentIDs = []
        }
        advanceToNextStop(runID: runID, state: &state)
    }

    /// Moves everything on the vehicle that is not yet home into this city's
    /// warehouse. Capacity is respected parcel by parcel: a full warehouse
    /// refuses cargo rather than silently swallowing it.
    func storeCarriedCargo(
        vehicleID: VehicleID,
        cityID: CityID,
        onlyLane: LaneID? = nil,
        state: inout GameState
    ) {
        guard let warehouse = state.warehouseSite(in: cityID) else { return }
        var free = freeStorage(of: warehouse, state: state)
        // A lane-scoped drop stores exactly the product the player routed here
        // (even if it is already home — an explicit consolidation choice); the
        // generic drop stores everything not yet at its final city.
        let carried = state.shipments
            .filter {
                guard $0.loadedVehicleID == vehicleID else { return false }
                if let onlyLane { return $0.offer.laneID == onlyLane }
                return !$0.isDeliverable(at: cityID)
            }
            // Most urgent first: if room runs out, the tight parcels are the
            // ones that stay on the truck and keep moving.
            .sorted { ($0.offer.expiresAt, $0.id.rawValue) < ($1.offer.expiresAt, $1.id.rawValue) }

        var storedCount = 0
        var storedMass = 0
        var refused = 0
        for shipment in carried {
            let load = shipment.offer.load
            guard load.massKg <= free.massKg, load.volumeM3 <= free.volumeM3 else {
                refused += 1
                continue
            }
            guard let index = state.shipments.firstIndex(where: { $0.id == shipment.id }) else { continue }
            if let routeID = shipment.assignedRouteID {
                creditHandover(shipmentIndex: index, to: routeID, state: &state)
            }
            state.shipments[index].location = .warehouse(warehouse.id)
            // Stored cargo belongs to the network, not to the route that
            // dropped it: any other route may pick it up next.
            state.shipments[index].assignedRouteID = nil
            free = LoadSize(massKg: free.massKg - load.massKg, volumeM3: free.volumeM3 - load.volumeM3)
            storedCount += 1
            storedMass += load.massKg
        }
        if storedCount > 0 {
            state.appendLog(.cargoStored(city: cityID, parcels: storedCount, massKg: storedMass))
        }
        if refused > 0 {
            state.appendLog(.warehouseFull(city: cityID, refusedParcels: refused))
        }
    }

    /// Loads a warehouse lot onto the vehicle, earliest deadline first.
    func collectFromWarehouse(
        vehicleID: VehicleID,
        cityID: CityID,
        lotKey: StorageLotKey,
        routeID: RouteID,
        state: inout GameState
    ) {
        guard let warehouse = state.warehouseSite(in: cityID),
              let vehicle = state.vehicle(vehicleID),
              let vehicleType = catalog.vehicleType(vehicle.typeID) else { return }
        let picked = loadableFromWarehouse(
            facilityID: warehouse.id,
            lotKey: lotKey,
            vehicle: vehicle,
            vehicleType: vehicleType,
            state: state
        )
        var mass = 0
        for jobID in picked {
            guard let index = state.shipments.firstIndex(where: { $0.id == jobID }) else { continue }
            state.shipments[index].location = .vehicle(vehicleID)
            state.shipments[index].assignedRouteID = routeID
            mass += state.shipments[index].offer.load.massKg
        }
        if !picked.isEmpty {
            state.appendLog(.cargoLoadedFromWarehouse(city: cityID, parcels: picked.count, massKg: mass))
        }
    }

    /// Appends to a route's rolling operating record. Missing route (already
    /// purged mid-wind-down) is fine: the record dies with the route.
    func addRouteStats(
        _ routeID: RouteID,
        state: inout GameState,
        _ mutate: (inout RouteStats) -> Void
    ) {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else { return }
        let before = state.routes[index].stats.profit
        mutate(&state.routes[index].stats)
        let delta = state.routes[index].stats.profit - before
        state.routes[index].stats.noteCashDelta(delta, at: state.clock)
    }

    /// Closes completed game days on every route so $/day steps at midnight
    /// even when a quiet lane booked no cash that day.
    func rollRouteDayStats(state: inout GameState) {
        for index in state.routes.indices {
            state.routes[index].stats.rollDays(to: state.clock)
        }
    }

    // MARK: - Handover settlement

    /// Margin a leg earns over its own cost when it hands cargo to the network
    /// rather than to the customer. Deliberately the same rate the market pays
    /// for spot freight: an internal leg is worth what an outside carrier would
    /// have charged for it, no more.
    var handoverMarginPercent: Int { catalog.economy.spotMarginPercent }

    /// Books a leg's share of a parcel's payout when it hands the parcel over.
    ///
    /// Without this, feeding a warehouse was structurally a loss: the dropping
    /// route paid the fuel and the dock wages while the payout waited for the
    /// finishing leg, so every hub-and-spoke network reported red no matter how
    /// well it ran. A leg now recovers what it spent plus the market margin,
    /// and the finishing leg books the rest — the journey still pays exactly
    /// once, and no cash moves here because none has arrived yet.
    ///
    /// Cost-plus rather than a distance split on purpose: the shuttle that
    /// sweeps a dock into the warehouse across town drives no kilometres at all
    /// and would otherwise be credited nothing for real work.
    func creditHandover(shipmentIndex: Int, to routeID: RouteID, state: inout GameState) {
        let shipment = state.shipments[shipmentIndex]
        let spent = shipment.carriedCost
        guard spent > 0 else { return }
        let remaining = max(0, shipment.offer.payout - shipment.settledPayout)
        guard remaining > 0 else {
            state.shipments[shipmentIndex].carriedCost = 0
            return
        }
        let asked = Money(
            (Double(spent) * (1 + Double(handoverMarginPercent) / 100)).rounded()
        )
        // Never more than the journey has left to pay: an expensive detour
        // cannot invent revenue for the routes behind it.
        let credit = min(asked, remaining)
        state.shipments[shipmentIndex].settledPayout += credit
        state.shipments[shipmentIndex].carriedCost = 0
        addRouteStats(routeID, state: &state) { $0.revenue += credit }
        state.recordDebug(
            .revenue,
            "HANDV r\(routeID.rawValue) j\(shipment.id.rawValue) "
                + "spent \(money(spent)) credited \(money(credit)) "
                + "of \(money(shipment.offer.payout)) remaining \(money(remaining - credit))"
        )
    }

    /// Spreads an operating cost across the parcels that were on board while it
    /// was incurred, by mass. This is what makes the handover credit fair: a
    /// leg's cost belongs to the freight it was carrying.
    func attributeCost(_ cost: Money, toCargoOf vehicleID: VehicleID, state: inout GameState) {
        guard cost > 0 else { return }
        let indices = state.shipments.indices.filter {
            state.shipments[$0].loadedVehicleID == vehicleID
        }
        guard !indices.isEmpty else { return }
        let totalMass = indices.reduce(0) { $0 + state.shipments[$1].offer.load.massKg }
        guard totalMass > 0 else { return }
        var assigned: Money = 0
        for (offset, index) in indices.enumerated() {
            let share: Money = offset == indices.count - 1
                ? cost - assigned
                : Money((Double(cost) * Double(state.shipments[index].offer.load.massKg)
                    / Double(totalMass)).rounded())
            assigned += share
            state.shipments[index].carriedCost += share
        }
    }

    func settleRouteDelivery(jobID: JobID, routeID: RouteID, state: inout GameState) {
        guard let index = state.shipments.firstIndex(where: { $0.id == jobID }) else { return }
        let offer = state.shipments[index].offer
        state.cash += offer.payout
        state.stats.totalRevenue += offer.payout
        state.stats.deliveredJobs += 1
        // Cash arrives whole, but the parcel may have changed hands: earlier
        // legs were already credited their share when they handed it over, so
        // this route books only what is left. Across the journey the payout is
        // counted exactly once.
        let earned = max(0, offer.payout - state.shipments[index].settledPayout)
        addRouteStats(routeID, state: &state) { $0.revenue += earned }
        // Revenue alone says nothing; the rate per km is what can be compared
        // against what the lane costs to run.
        let perKm = offer.distanceKm > 0 ? Double(offer.payout) / offer.distanceKm : 0
        state.recordDebug(
            .revenue,
            delta: offer.payout,
            "DELIV r\(routeID.rawValue) \(short(offer.origin))→\(short(offer.destination)) "
                + "\(kg(offer.load.massKg)) \(km(offer.distanceKm)) "
                + "rev \(money(offer.payout)) @\(rate(perKm))/km"
        )
        state.shipments.remove(at: index)
        state.appendLog(.routeShipmentDelivered(
            routeID: routeID,
            jobID: jobID,
            destination: offer.destination,
            revenue: offer.payout
        ))
    }

}
