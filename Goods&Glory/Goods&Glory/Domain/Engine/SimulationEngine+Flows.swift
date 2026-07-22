//
//  SimulationEngine+Lanes.swift
//  Goods&Glory
//
//  Persistent freight lanes: dock accrual, parcel claiming and one-tap
//  dispatch. This is where the world's standing demand lives.
//

import Foundation

extension SimulationEngine {
    // MARK: - Freight lanes

    /// The world breathes here: every lane's origin dock gains the freight its
    /// rate produced since the last tick. Waiting freight is capped by the
    /// patience window so an unserved dock cannot grow without bound.
    func accrueLanes(state: inout GameState) {
        let tickAt = state.nextLaneTickAt
        state.nextLaneTickAt = tickAt + LaneConfig.tickMinutes
        let config = catalog.economy.lanes
        let week = tickAt.totalMinutes / (7 * GameState.minutesPerDay)

        for lane in catalog.lanes {
            let fullRate = lane.ratePerDayKg(
                week: week,
                worldSeed: state.config.seed,
                swingPercent: config.weeklySwingPercent
            )
            // Tonnage promised to a signed contract is posted as contract
            // parcels on that contract's own cadence, so it must not also pile
            // up at the dock as spot freight — that would sell it twice.
            let free = ContractDestination.fullShareBps - committedShareBps(of: lane.id, state: state)
            let rate = fullRate * free / ContractDestination.fullShareBps
            let gained = rate * LaneConfig.tickMinutes / GameState.minutesPerDay
            let capacity = max(gained, rate * config.parcelPatienceMinutes / GameState.minutesPerDay)
            let accrued = (state.laneAccrualKg[lane.id] ?? 0) + gained
            state.laneAccrualKg[lane.id] = min(accrued, capacity)
        }
    }

    /// Waiting freight at a lane's origin dock right now.
    func waitingLaneKg(_ laneID: LaneID, state: GameState) -> Int {
        state.laneAccrualKg[laneID] ?? 0
    }

    /// One-tap lane service: builds a two-stop shuttle route (claim at the
    /// origin dock, deliver everything at the destination), assigns the vehicle
    /// and starts it. The shuttle keeps serving the lane — including the empty
    /// return leg the player will learn to hate — until stopped or deleted.
    func dispatchVehicleToLane(
        _ laneID: LaneID,
        vehicleID: VehicleID,
        state: inout GameState
    ) throws {
        guard let lane = catalog.lane(laneID), state.vehicle(vehicleID) != nil else {
            throw CommandError.unknownReference
        }
        guard state.isVehicleIdle(vehicleID), state.route(of: vehicleID) == nil else {
            throw CommandError.vehicleAlreadyAssigned
        }

        let originName = catalog.city(lane.originCityID)?.name ?? lane.originCityID.rawValue
        let destinationName = catalog.city(lane.destinationCityID)?.name
            ?? lane.destinationCityID.rawValue
        let route = Route(
            id: RouteID(rawValue: state.issueID()),
            name: "\(originName) → \(destinationName)",
            stops: [
                RouteStop(id: state.issueID(), cityID: lane.originCityID, task: .pickupLane(laneID)),
                RouteStop(id: state.issueID(), cityID: lane.destinationCityID, task: .deliverLane(laneID, .destination))
            ],
            vehicleIDs: [],
            isRunning: true,
            stats: {
                var stats = RouteStats()
                stats.markStarted(at: state.clock)
                return stats
            }()
        )
        state.routes.append(route)
        state.appendLog(.routeStarted(routeID: route.id))
        state.recordDebug(
            .decision,
            "DISP  r\(route.id.rawValue) v\(vehicleID.rawValue) → lane "
                + "\(short(lane.originCityID))→\(short(lane.destinationCityID)) "
                + "\(kg(lane.baseRatePerDayKg))/d waiting \(kg(waitingLaneKg(laneID, state: state)))"
        )
        try assignVehicleToRoute(routeID: route.id, vehicleID: vehicleID, state: &state)
    }

    /// Mints shipments from a lane's waiting freight for a vehicle at the dock:
    /// parcels sized by the product's shipment bounds, priced for the loading
    /// vehicle at the spot rate, until the vehicle is full or the dock is empty.
    /// Returns the claimed shipment ids; the accrual is debited immediately.
    func claimLaneParcels(
        lane: FreightLane,
        vehicle: Vehicle,
        vehicleType: VehicleTypeDefinition,
        routeID: RouteID,
        reservedLoad: LoadSize = LoadSize(massKg: 0, volumeM3: 0),
        state: inout GameState
    ) -> [JobID] {
        guard let product = catalog.product(lane.productID),
              let distanceKm = catalog.roadDistanceKm(from: lane.originCityID, to: lane.destinationCityID)
        else { return [] }
        let massStepKg = ProductDefinition.shipmentMassStepKg
        var available = state.laneAccrualKg[lane.id] ?? 0
        // Reserved covers parcels already claimed for this stop but not yet
        // loaded onto the vehicle (mid-service top-up).
        var running = combinedLoad(state.cargoLoad(of: vehicle.id), reservedLoad)
        var claimed: [JobID] = []

        while available >= product.minimumShipmentMassKg {
            // Largest parcel that respects the product's bounds, the dock's
            // stock and the vehicle's remaining mass and volume.
            let volumeLimitKg = Int(
                ((vehicleType.capacity.volumeM3 - running.volumeM3)
                    / product.densityM3PerTon * 1000).rounded(.down)
            )
            let massLimitKg = vehicleType.capacity.massKg - running.massKg
            let cap = min(available, product.maximumShipmentMassKg, massLimitKg, volumeLimitKg)
            let massKg = (cap / massStepKg) * massStepKg
            guard massKg >= product.minimumShipmentMassKg else { break }

            let load = parcelLoad(productID: lane.productID, massKg: massKg)
            let payout = freightPayout(
                origin: lane.originCityID,
                destination: lane.destinationCityID,
                distanceKm: distanceKm,
                load: load,
                vehicleType: vehicleType,
                state: state
            )
            let offer = JobOffer(
                id: JobID(rawValue: state.issueID()),
                origin: lane.originCityID,
                destination: lane.destinationCityID,
                productID: lane.productID,
                load: load,
                payout: payout,
                distanceKm: distanceKm,
                urgency: .normal,
                source: .lane,
                contractID: nil,
                laneID: lane.id,
                originFirmID: lane.originFirmID,
                destinationFirmID: lane.destinationFirmID,
                createdAt: state.clock,
                // Soft ordering deadline only — spot freight carries no penalty.
                expiresAt: state.clock + catalog.economy.lanes.parcelPatienceMinutes
            )
            state.shipments.append(Shipment(
                id: offer.id,
                offer: offer,
                location: .address(lane.originCityID),
                assignedRouteID: routeID
            ))
            claimed.append(offer.id)
            available -= massKg
            running = combinedLoad(running, load)
        }
        state.laneAccrualKg[lane.id] = available
        if !claimed.isEmpty {
            let claimedMass = state.shipments
                .filter { claimed.contains($0.id) }
                .reduce(0) { $0 + $1.offer.load.massKg }
            let revenue = state.shipments
                .filter { claimed.contains($0.id) }
                .reduce(0) { $0 + $1.offer.payout }
            state.recordDebug(
                .world,
                "CLAIM r\(routeID.rawValue) v\(vehicle.id.rawValue) \(short(lane.originCityID)) "
                    + "\(claimed.count)× \(kg(claimedMass)) "
                    + "fill \(pct(util(load: running, capacity: vehicleType.capacity))) "
                    + "worth \(money(revenue)) · dock left \(kg(available))"
            )
        }
        return claimed
    }

    /// Size of one posted parcel for a contract cycle.
    ///
    /// Bounded above by what the reference vehicle can carry (mass *and*
    /// volume) and by the cycle's own volume — promising a full trailer when
    /// the lane only produces half of one is how a contract starves the truck
    /// assigned to it. Bounded below by the product's minimum shipment.
    /// Multi-drop splits the cycle across its drops, so each drop still gets a
    /// parcel worth sending.
    func parcelSize(
        product: ProductDefinition,
        capacity: LoadSize,
        cycleVolumeKg: Int,
        dropCount: Int
    ) -> LoadSize? {
        let step = ProductDefinition.shipmentMassStepKg
        let volumeLimitKg = Int((capacity.volumeM3 / product.densityM3PerTon * 1000).rounded(.down))
        let perDropKg = cycleVolumeKg / max(1, dropCount)
        // Never a parcel that fills the reference truck to the brim. A 5.0 t
        // commitment on a 5.0 t truck can only travel on a completely empty
        // vehicle, so one 150 kg spot claim earlier on the lap locked it out and
        // it sat on the dock for another round, ageing towards a penalty.
        // Leaving a tenth of the deck free is what lets committed and spot
        // freight share a lap at all.
        let ceilingKg = min(
            product.maximumShipmentMassKg,
            capacity.massKg * 9 / 10,
            volumeLimitKg,
            max(perDropKg, product.minimumShipmentMassKg)
        )
        let massKg = (ceilingKg / step) * step
        guard massKg >= product.minimumShipmentMassKg else { return nil }
        return parcelLoad(productID: product.id, massKg: massKg)
    }

    func weightedPick<T>(_ items: [(T, Double)], rng: inout SeededRNG) -> T? {
        let total = items.reduce(0.0) { $0 + max(0, $1.1) }
        guard total > 0 else { return items.first?.0 }
        var roll = Double.random(in: 0..<total, using: &rng)
        for (item, weight) in items {
            roll -= max(0, weight)
            if roll < 0 { return item }
        }
        return items.last?.0
    }

    func weightedPick<T>(_ items: [(T, UInt16)], rng: inout SeededRNG) -> T? {
        weightedPick(items.map { ($0.0, Double($0.1)) }, rng: &rng)
    }

}
