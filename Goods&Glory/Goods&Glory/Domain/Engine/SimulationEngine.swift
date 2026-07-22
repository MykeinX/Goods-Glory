//
//  SimulationEngine.swift
//  Goods&Glory
//
//  Pure simulation core. Advances only through explicit commands and explicit
//  amounts of game time. No wall clock, no UI, no persistence. The same
//  catalog, initial state, seed and command sequence always produce the same
//  resulting state.
//

import Foundation

struct SimulationEngine: Sendable {
    let catalog: GameCatalog

    init(catalog: GameCatalog) {
        self.catalog = catalog
    }

    // MARK: - Commands

    func apply(_ command: GameCommand, to state: inout GameState) throws {
        switch command {
        case .buyVehicle(let typeID):
            try buyVehicle(typeID, state: &state)
        case .acceptJob(let offerID, let vehicleID):
            try acceptJob(offerID: offerID, vehicleID: vehicleID, state: &state)
        case .dispatchVehicleToLane(let laneID, let vehicleID):
            try dispatchVehicleToLane(laneID, vehicleID: vehicleID, state: &state)
        case .signContract(let contractID):
            try signContract(contractID, state: &state)
        case .assignVehicleToContract(let contractID, let vehicleID):
            try assignVehicleToContract(contractID, vehicleID: vehicleID, state: &state)
        case .cancelContract(let contractID):
            try cancelContract(contractID, state: &state)
        case .installModule(let kind, let cityID):
            try installModule(kind: kind, cityID: cityID, state: &state)
        case .upgradeModule(let kind, let cityID):
            try upgradeModule(kind: kind, cityID: cityID, state: &state)
        case .removeModule(let kind, let cityID):
            try removeModule(kind: kind, cityID: cityID, state: &state)
        case .addNetworkTaskToRoute(let routeID, let visitStopID, let task):
            try addNetworkTaskToRoute(
                routeID: routeID,
                visitStopID: visitStopID,
                task: task,
                state: &state
            )
        case .createRoute(let name):
            createRoute(name: name, state: &state)
        case .renameRoute(let routeID, let name):
            try renameRoute(routeID, name: name, state: &state)
        case .addTravelStop(let routeID, let cityID):
            try addTravelStop(routeID: routeID, cityID: cityID, state: &state)
        case .removeRouteStop(let routeID, let stopID):
            try removeRouteStop(routeID: routeID, stopID: stopID, state: &state)
        case .moveRouteStop(let routeID, let stopID, let offset):
            try moveRouteStop(routeID: routeID, stopID: stopID, offset: offset, state: &state)
        case .addContractTaskToRoute(let routeID, let visitStopID, let contractID, let action):
            try addContractTaskToRoute(
                routeID: routeID,
                visitStopID: visitStopID,
                contractID: contractID,
                action: action,
                state: &state
            )
        case .reorderRouteVisits(let routeID, let orderedVisitIDs):
            try reorderRouteVisits(routeID: routeID, orderedVisitIDs: orderedVisitIDs, state: &state)
        case .removeRouteVisit(let routeID, let visitStopID):
            try removeRouteVisit(routeID: routeID, visitStopID: visitStopID, state: &state)
        case .addJobToRoute(let offerID, let routeID):
            try addJobToRoute(offerID: offerID, routeID: routeID, state: &state)
        case .removeJobFromRoute(let jobID, let routeID):
            try removeJobFromRoute(jobID: jobID, routeID: routeID, state: &state)
        case .assignVehicleToRoute(let routeID, let vehicleID):
            try assignVehicleToRoute(routeID: routeID, vehicleID: vehicleID, state: &state)
        case .unassignVehicleFromRoute(let routeID, let vehicleID):
            try unassignVehicleFromRoute(routeID: routeID, vehicleID: vehicleID, state: &state)
        case .startRoute(let routeID):
            try startRoute(routeID, state: &state)
        case .stopRoute(let routeID):
            try stopRoute(routeID, state: &state)
        case .deleteRoute(let routeID):
            try deleteRoute(routeID, state: &state)
        }
    }

    func buyVehicle(_ typeID: VehicleTypeID, state: inout GameState) throws {
        guard let vehicleType = catalog.vehicleType(typeID) else { throw CommandError.unknownReference }
        guard state.cash >= vehicleType.purchasePrice else {
            throw CommandError.insufficientFunds(required: vehicleType.purchasePrice)
        }
        state.cash -= vehicleType.purchasePrice
        let vehicle = Vehicle(
            id: VehicleID(rawValue: state.issueID()),
            typeID: typeID,
            cityID: state.config.hqCity,
            assignedJobID: nil,
            odometerKm: 0
        )
        state.vehicles.append(vehicle)
        state.appendLog(.vehiclePurchased(typeID: typeID, city: vehicle.cityID))
        state.recordDebug(
            .capital,
            delta: -vehicleType.purchasePrice,
            "BUY   v\(vehicle.id.rawValue) \(vehicleType.name) cap \(kg(vehicleType.capacity.massKg)) "
                + "\(money(vehicleType.purchasePrice)) upkeep \(money(Money(vehicleType.fixedCostPerDay)))/d"
        )
    }

    func acceptJob(offerID: JobID, vehicleID: VehicleID, state: inout GameState) throws {
        guard let offerIndex = state.offers.firstIndex(where: { $0.id == offerID }),
              let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == vehicleID }),
              let vehicleType = catalog.vehicleType(state.vehicles[vehicleIndex].typeID) else {
            throw CommandError.unknownReference
        }
        let offer = state.offers[offerIndex]
        let vehicle = state.vehicles[vehicleIndex]

        guard state.isVehicleIdle(vehicleID) else { throw CommandError.vehicleBusy }
        guard state.clock < offer.expiresAt else { throw CommandError.offerExpired }
        guard offer.load.fits(in: vehicleType.capacity) else { throw CommandError.loadExceedsCapacity }
        // A lane with no road path is not acceptable work, even though the
        // traversal list itself is no longer kept.
        guard catalog.shortestRoute(from: offer.origin, to: offer.destination) != nil else {
            throw CommandError.noRoute
        }
        guard let deadheadRoute = catalog.shortestRoute(from: vehicle.cityID, to: offer.origin) else {
            throw CommandError.noRoute
        }

        let startsWithDeadhead = deadheadRoute.distanceKm > 0
        let firstPhase: JobPhase = startsWithDeadhead ? .deadheading : .loading
        let nominalFirst = startsWithDeadhead
            ? travelMinutes(distanceKm: deadheadRoute.distanceKm, speedKmh: vehicleType.speedKmh)
            : loadingMinutes(at: offer.origin)
        let firstPhaseMinutes = variedDurationMinutes(
            base: nominalFirst,
            worldSeed: state.config.seed,
            kind: startsWithDeadhead ? "job_deadhead" : "job_load",
            vehicleID: vehicleID,
            eventID: offer.id.rawValue,
            at: state.clock
        )

        // `mainRoute` is still required: a job with no road path is invalid, and
        // its distance drives the delivery clock. Only the traversal lists are
        // dropped — they were stored on every job and serialized into every
        // save while nothing ever read them.
        let job = ActiveJob(
            id: offer.id,
            offer: offer,
            vehicleID: vehicleID,
            deadheadKm: deadheadRoute.distanceKm,
            startedAt: state.clock,
            phase: firstPhase,
            phaseStartedAt: state.clock,
            phaseEndsAt: state.clock + firstPhaseMinutes
        )

        state.offers.remove(at: offerIndex)
        state.vehicles[vehicleIndex].assignedJobID = job.id
        state.activeJobs.append(job)
        state.appendLog(.jobAccepted(jobID: job.id, origin: offer.origin, destination: offer.destination))
    }

    func signContract(_ contractID: ContractID, state: inout GameState) throws {
        guard let index = state.contractOffers.firstIndex(where: { $0.id == contractID }) else {
            throw CommandError.unknownReference
        }
        let offer = state.contractOffers[index]
        guard state.clock < offer.expiresAt else { throw CommandError.offerExpired }
        // The branch may have been demolished between posting and signing.
        guard state.hasOperationalOffice(in: offer.origin) else {
            throw CommandError.branchRequired
        }

        let signed = ActiveContract(
            id: offer.id,
            origin: offer.origin,
            productID: offer.productID,
            archetype: offer.archetype,
            destinations: offer.destinations,
            referenceVehicleTypeID: offer.referenceVehicleTypeID,
            parcelMassKg: offer.parcelMassKg,
            volumePerCycleKg: offer.volumePerCycleKg,
            shipmentIntervalMinutes: offer.shipmentIntervalMinutes,
            deliveryWindowMinutes: offer.deliveryWindowMinutes,
            signedAt: state.clock,
            endsAt: offer.durationDays.map { state.clock + $0 * GameState.minutesPerDay },
            // Lead time is the promise the game makes back to the player: time
            // to position vehicles before the first parcel is on the clock.
            nextShipmentAt: state.clock + offer.leadTimeMinutes,
            shipmentsIssued: 0,
            shipmentsCompleted: 0,
            shipmentsMissed: 0,
            penaltiesPaid: 0,
            cancellationRequestedAt: nil,
            originFirmID: offer.originFirmID
        )
        state.contractOffers.remove(at: index)
        state.activeContracts.append(signed)
        state.appendLog(.contractSigned(
            contractID: signed.id,
            origin: signed.origin,
            destination: signed.destination
        ))
        let brief = brief(for: signed)
        state.recordDebug(
            .decision,
            "SIGN  c\(signed.id.rawValue) \(signed.archetype.rawValue) "
                + "\(short(signed.origin))→\(short(signed.destination)) "
                + "\(kg(signed.volumePerCycleKg))/\(signed.shipmentIntervalMinutes / 1440)d "
                + "in \(kg(signed.parcelMassKg)) parcels @\(money(signed.payoutPerShipment)) "
                + "locks \(signed.destinations.map { "\($0.committedShareBps / 100)%" }.joined(separator: "+")) of lane"
                + (brief.map {
                    " · \(kg($0.committedKgPerDay))/d reserved, +\(money($0.premiumPerDay))/d"
                        + " over spot, \(Int(($0.fleetLoad * 100).rounded()))% of a truck"
                } ?? "")
        )
    }

    /// Safe close (GDD lifecycle step 7): stop posting, let committed parcels
    /// finish. Cargo in flight is never destroyed.
    func cancelContract(_ contractID: ContractID, state: inout GameState) throws {
        guard let index = state.activeContracts.firstIndex(where: { $0.id == contractID }) else {
            throw CommandError.unknownReference
        }
        guard state.activeContracts[index].cancellationRequestedAt == nil else { return }
        state.activeContracts[index].cancellationRequestedAt = state.clock
        state.appendLog(.contractCancellationRequested(contractID: contractID))
    }

    /// One-tap contract crewing: ensures an ordinary route covering the
    /// contract exists, assigns the vehicle and starts it. The route belongs
    /// to no one — it is a lane. On single-destination lanes it also claims
    /// the lanes running the same way, so the dock visit tops the vehicle off with spot
    /// freight after the contract parcels (SLA cargo first, spot fills the
    /// rest) and the lane keeps earning when the contract someday ends.
    func assignVehicleToContract(
        _ contractID: ContractID,
        vehicleID: VehicleID,
        state: inout GameState
    ) throws {
        guard let contract = state.activeContract(contractID),
              let vehicle = state.vehicle(vehicleID),
              let vehicleType = catalog.vehicleType(vehicle.typeID) else {
            throw CommandError.unknownReference
        }
        guard state.route(of: vehicleID) == nil else { throw CommandError.vehicleAlreadyAssigned }
        guard contractLoad(contract).fits(in: vehicleType.capacity) else {
            throw CommandError.loadExceedsCapacity
        }

        let routeID: RouteID
        if let existing = state.route(serving: contractID) {
            routeID = existing.id
        } else {
            let originName = catalog.city(contract.origin)?.name ?? contract.origin.rawValue
            let destinationName = catalog.city(contract.destination)?.name ?? contract.destination.rawValue
            var stops = [
                RouteStop(id: state.issueID(), cityID: contract.origin, task: .pickupContract(contractID))
            ]
            if contract.isMultiDrop {
                // Multi-drop lanes get every drop on the lap, so one-tap
                // crewing produces a route that can satisfy the contract.
                for destination in contract.destinations {
                    stops.append(RouteStop(
                        id: state.issueID(),
                        cityID: destination.cityID,
                        task: .deliverContract(contractID)
                    ))
                }
            } else {
                // Lanes running the same way ride along: claimed after the contract task
                // at the same dock, delivered by the same catch-all stop.
                for lane in catalog.lanes(from: contract.origin)
                where lane.destinationCityID == contract.destination {
                    stops.append(RouteStop(
                        id: state.issueID(),
                        cityID: contract.origin,
                        task: .pickupLane(lane.id)
                    ))
                }
                stops.append(RouteStop(
                    id: state.issueID(),
                    cityID: contract.destination,
                    task: .deliverAll
                ))
            }
            let suffix = contract.isMultiDrop ? " +\(contract.destinations.count - 1)" : ""
            let route = Route(
                id: RouteID(rawValue: state.issueID()),
                name: "\(originName) → \(destinationName)\(suffix)",
                stops: stops,
                vehicleIDs: [],
                isRunning: true,
                stats: {
                    var stats = RouteStats()
                    stats.markStarted(at: state.clock)
                    return stats
                }()
            )
            state.routes.append(route)
            routeID = route.id
            state.appendLog(.routeStarted(routeID: routeID))
        }
        try assignVehicleToRoute(routeID: routeID, vehicleID: vehicleID, state: &state)
        if let index = state.routes.firstIndex(where: { $0.id == routeID }), !state.routes[index].isRunning {
            state.routes[index].isRunning = true
            state.appendLog(.routeStarted(routeID: routeID))
        }
        syncRouteRuns(state: &state)
    }

    /// The load of one parcel of this contract (volume from product density).
    func contractLoad(_ contract: ActiveContract) -> LoadSize {
        parcelLoad(productID: contract.productID, massKg: contract.parcelMassKg)
    }

}
