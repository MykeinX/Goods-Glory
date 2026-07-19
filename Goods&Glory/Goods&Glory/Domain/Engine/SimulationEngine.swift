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
        case .signContract(let contractID):
            try signContract(contractID, state: &state)
        case .assignVehicleToContract(let contractID, let vehicleID):
            try assignVehicleToContract(contractID, vehicleID: vehicleID, state: &state)
        case .unassignVehicleFromContract(let contractID, let vehicleID):
            try unassignVehicleFromContract(contractID, vehicleID: vehicleID, state: &state)
        case .cancelContract(let contractID):
            try cancelContract(contractID, state: &state)
        case .buildFacility(let kind, let cityID):
            try buildFacility(kind: kind, cityID: cityID, state: &state)
        case .upgradeFacility(let facilityID):
            try upgradeFacility(facilityID, state: &state)
        case .demolishFacility(let facilityID):
            try demolishFacility(facilityID, state: &state)
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

    private func buyVehicle(_ typeID: VehicleTypeID, state: inout GameState) throws {
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
    }

    private func acceptJob(offerID: JobID, vehicleID: VehicleID, state: inout GameState) throws {
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
        guard let mainRoute = catalog.shortestRoute(from: offer.origin, to: offer.destination) else {
            throw CommandError.noRoute
        }
        guard let deadheadRoute = catalog.shortestRoute(from: vehicle.cityID, to: offer.origin) else {
            throw CommandError.noRoute
        }

        let startsWithDeadhead = deadheadRoute.distanceKm > 0
        let firstPhase: JobPhase = startsWithDeadhead ? .deadheading : .loading
        let firstPhaseMinutes = startsWithDeadhead
            ? travelMinutes(distanceKm: deadheadRoute.distanceKm, speedKmh: vehicleType.speedKmh)
            : loadingMinutes(at: offer.origin)

        let job = ActiveJob(
            id: offer.id,
            offer: offer,
            vehicleID: vehicleID,
            deadheadRoute: startsWithDeadhead ? deadheadRoute.traversals : [],
            deadheadKm: deadheadRoute.distanceKm,
            route: mainRoute.traversals,
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

    private func signContract(_ contractID: ContractID, state: inout GameState) throws {
        guard let index = state.contractOffers.firstIndex(where: { $0.id == contractID }) else {
            throw CommandError.unknownReference
        }
        let offer = state.contractOffers[index]
        guard state.clock < offer.expiresAt else { throw CommandError.offerExpired }
        // The branch may have been demolished between posting and signing.
        guard state.hasOperationalBranch(in: offer.origin) else {
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
    }

    /// Safe close (GDD lifecycle step 7): stop posting, let committed parcels
    /// finish. Cargo in flight is never destroyed.
    private func cancelContract(_ contractID: ContractID, state: inout GameState) throws {
        guard let index = state.activeContracts.firstIndex(where: { $0.id == contractID }) else {
            throw CommandError.unknownReference
        }
        guard state.activeContracts[index].cancellationRequestedAt == nil else { return }
        state.activeContracts[index].cancellationRequestedAt = state.clock
        state.appendLog(.contractCancellationRequested(contractID: contractID))
    }

    /// One-tap contract crewing: ensures the contract's two-stop route exists,
    /// assigns the vehicle and starts the route. The route stays fully editable.
    private func assignVehicleToContract(
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
        if let existing = state.route(forContract: contractID) {
            routeID = existing.id
        } else {
            let originName = catalog.city(contract.origin)?.name ?? contract.origin.rawValue
            let destinationName = catalog.city(contract.destination)?.name ?? contract.destination.rawValue
            // Multi-drop lanes get every drop on the lap, so one-tap crewing
            // produces a route that can actually satisfy the contract.
            var stops = [
                RouteStop(id: state.issueID(), cityID: contract.origin, task: .pickupContract(contractID))
            ]
            for destination in contract.destinations {
                stops.append(RouteStop(
                    id: state.issueID(),
                    cityID: destination.cityID,
                    task: .deliverContract(contractID)
                ))
            }
            let suffix = contract.isMultiDrop ? " +\(contract.destinations.count - 1)" : ""
            let route = Route(
                id: RouteID(rawValue: state.issueID()),
                name: "\(originName) → \(destinationName)\(suffix)",
                contractID: contractID,
                stops: stops,
                vehicleIDs: [],
                isRunning: true
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

    private func unassignVehicleFromContract(
        _ contractID: ContractID,
        vehicleID: VehicleID,
        state: inout GameState
    ) throws {
        guard let route = state.route(forContract: contractID) else {
            throw CommandError.unknownReference
        }
        try unassignVehicleFromRoute(routeID: route.id, vehicleID: vehicleID, state: &state)
    }

    /// The load of one parcel of this contract (volume from product density).
    func contractLoad(_ contract: ActiveContract) -> LoadSize {
        parcelLoad(productID: contract.productID, massKg: contract.parcelMassKg)
    }

    // MARK: - Facilities

    /// Price, duration and capacity of a facility level in one city. Read-only,
    /// used by both the command path and the UI so the player is never quoted
    /// a number the engine will not honour.
    func quote(kind: FacilityKind, level: Int, city cityID: CityID) -> FacilityQuote? {
        guard let city = catalog.city(cityID) else { return nil }
        return FacilityEconomics.quote(
            kind: kind,
            level: level,
            city: city,
            config: catalog.economy.facilities
        )
    }

    func upgradeQuote(for facility: Facility) -> FacilityQuote? {
        guard let city = catalog.city(facility.cityID) else { return nil }
        return FacilityEconomics.upgradeQuote(
            from: facility.level,
            kind: facility.kind,
            city: city,
            config: catalog.economy.facilities
        )
    }

    private func buildFacility(kind: FacilityKind, cityID: CityID, state: inout GameState) throws {
        guard catalog.city(cityID) != nil else { throw CommandError.unknownReference }
        guard state.facility(kind: kind, in: cityID) == nil else {
            throw CommandError.facilityAlreadyExists
        }
        guard let quote = quote(kind: kind, level: 1, city: cityID) else {
            throw CommandError.unknownReference
        }
        guard state.cash >= quote.cost else {
            throw CommandError.insufficientFunds(required: quote.cost)
        }

        state.cash -= quote.cost
        state.stats.totalCost += quote.cost
        let facility = Facility(
            id: FacilityID(rawValue: state.issueID()),
            cityID: cityID,
            kind: kind,
            level: 1,
            isHeadquarters: false,
            foundedAt: state.clock,
            operationalAt: state.clock + quote.buildMinutes,
            upgradingTo: nil,
            upgradeEndsAt: nil
        )
        state.facilities.append(facility)
        state.appendLog(.facilityConstructionStarted(
            facilityID: facility.id,
            kind: kind,
            city: cityID,
            level: 1
        ))
    }

    private func upgradeFacility(_ facilityID: FacilityID, state: inout GameState) throws {
        guard let index = state.facilities.firstIndex(where: { $0.id == facilityID }) else {
            throw CommandError.unknownReference
        }
        let facility = state.facilities[index]
        guard facility.isOperational(at: state.clock), !facility.isUpgrading else {
            throw CommandError.facilityNotAvailable
        }
        guard facility.level < catalog.economy.facilities.maxLevel(for: facility.kind),
              let quote = upgradeQuote(for: facility) else {
            throw CommandError.facilityNotAvailable
        }
        guard state.cash >= quote.cost else {
            throw CommandError.insufficientFunds(required: quote.cost)
        }

        state.cash -= quote.cost
        state.stats.totalCost += quote.cost
        state.facilities[index].upgradingTo = facility.level + 1
        state.facilities[index].upgradeEndsAt = state.clock + quote.buildMinutes
        state.appendLog(.facilityConstructionStarted(
            facilityID: facility.id,
            kind: facility.kind,
            city: facility.cityID,
            level: facility.level + 1
        ))
    }

    private func demolishFacility(_ facilityID: FacilityID, state: inout GameState) throws {
        guard let index = state.facilities.firstIndex(where: { $0.id == facilityID }) else {
            throw CommandError.unknownReference
        }
        let facility = state.facilities[index]
        guard !facility.isHeadquarters else { throw CommandError.cannotDemolishHeadquarters }
        guard state.shipments(storedIn: facilityID).isEmpty else {
            throw CommandError.warehouseNotEmpty
        }
        state.facilities.remove(at: index)
        state.appendLog(.facilityDemolished(kind: facility.kind, city: facility.cityID))
    }

    /// Completes construction and upgrades whose time has come. Called from the
    /// event loop so partial and whole `advance` calls land identically.
    private func completeFinishedConstruction(state: inout GameState) {
        for index in state.facilities.indices {
            let facility = state.facilities[index]
            if facility.operationalAt <= state.clock, !facility.hasAnnouncedCompletion {
                state.facilities[index].hasAnnouncedCompletion = true
                // The free HQ branch exists from minute zero; it is not news.
                if !facility.isHeadquarters {
                    state.appendLog(.facilityCompleted(
                        facilityID: facility.id,
                        kind: facility.kind,
                        city: facility.cityID,
                        level: facility.level
                    ))
                }
            }
            guard let target = facility.upgradingTo,
                  let endsAt = facility.upgradeEndsAt,
                  endsAt <= state.clock else { continue }
            state.facilities[index].level = target
            state.facilities[index].upgradingTo = nil
            state.facilities[index].upgradeEndsAt = nil
            state.appendLog(.facilityCompleted(
                facilityID: facility.id,
                kind: facility.kind,
                city: facility.cityID,
                level: target
            ))
        }
    }

    /// Daily upkeep of every standing facility, scaled by its city.
    func facilityUpkeepPerDay(state: GameState) -> Money {
        state.facilities.reduce(0) { total, facility in
            guard let quote = quote(kind: facility.kind, level: facility.level, city: facility.cityID)
            else { return total }
            return total + quote.upkeepPerDay
        }
    }

    /// Branch payout bonus on lanes touching a city: the HQ home-field premium
    /// plus whatever a high-level branch adds there.
    func branchLanePremium(city cityID: CityID, state: GameState) -> Double {
        var premium = 0.0
        if cityID == state.config.hqCity {
            premium += Double(catalog.economy.hqLanePremiumPercent) / 100
        }
        if let branch = state.branch(in: cityID), branch.isOperational(at: state.clock),
           let quote = quote(kind: .branch, level: branch.level, city: cityID) {
            premium += quote.lanePremium
        }
        return premium
    }

    /// Total payout multiplier for a lane, counting both endpoints.
    func lanePremiumFactor(origin: CityID, destination: CityID, state: GameState) -> Double {
        1 + branchLanePremium(city: origin, state: state)
            + branchLanePremium(city: destination, state: state)
    }

    // MARK: - Time

    /// Advances the simulation by an explicit amount of game minutes,
    /// processing intermediate events in strict chronological order.
    func advance(_ state: inout GameState, by minutes: Int) {
        precondition(minutes >= 0, "cannot advance backwards")
        let target = state.clock + minutes

        while true {
            var nextEventAt = target
            for job in state.activeJobs where job.phaseEndsAt < nextEventAt {
                nextEventAt = job.phaseEndsAt
            }
            if state.nextOfferBatchAt < nextEventAt {
                nextEventAt = state.nextOfferBatchAt
            }
            if state.nextContractBatchAt < nextEventAt {
                nextEventAt = state.nextContractBatchAt
            }
            for contract in state.activeContracts {
                if contract.nextShipmentAt < nextEventAt, !contract.isClosing(at: state.clock) {
                    nextEventAt = contract.nextShipmentAt
                }
                if let endsAt = contract.endsAt, endsAt < nextEventAt {
                    nextEventAt = endsAt
                }
            }
            // Construction landings are events too: a branch that finishes
            // mid-chunk must start granting contracts at that exact minute.
            for facility in state.facilities {
                if facility.operationalAt < nextEventAt, !facility.hasAnnouncedCompletion {
                    nextEventAt = facility.operationalAt
                }
                if let endsAt = facility.upgradeEndsAt, endsAt < nextEventAt {
                    nextEventAt = endsAt
                }
            }
            // Contract shipment deadlines are penalty events and must be
            // processed at their exact time for deterministic settlement.
            for offer in state.offers where offer.source == .contract && offer.expiresAt < nextEventAt {
                nextEventAt = offer.expiresAt
            }
            for run in state.routeRuns where run.phaseEndsAt < nextEventAt {
                nextEventAt = run.phaseEndsAt
            }
            state.clock = max(state.clock, nextEventAt)

            completeFinishedConstruction(state: &state)
            chargeFixedCostsIfNeeded(state: &state)
            removeExpiredOffers(state: &state)
            removeExpiredContractOffers(state: &state)

            if state.nextOfferBatchAt <= state.clock {
                generateOfferBatch(state: &state)
            }
            // Runs every pass, not just on the tick: a truck that just finished
            // a delivery finds work waiting instead of an empty board.
            ensureLocalSpotOffers(state: &state)
            if state.nextContractBatchAt <= state.clock {
                generateContractOfferBatch(state: &state)
            } else {
                // Self-heal: a branch board that emptied mid-interval (a signed
                // lane, staggered expiries) refills now rather than tomorrow.
                replenishContractOffers(state: &state)
            }
            postDueContractShipments(state: &state)
            expireFinishedContracts(state: &state)

            let dueJobIDs = state.activeJobs
                .filter { $0.phaseEndsAt <= state.clock }
                .map(\.id)
                .sorted { $0.rawValue < $1.rawValue }
            for jobID in dueJobIDs {
                advancePhase(of: jobID, state: &state)
            }
            // Waiting-for-cargo runs use a distant sentinel end and are woken
            // by syncRouteRuns instead; timed waits (lap guard) come due here.
            let dueRunIDs = state.routeRuns
                .filter { $0.phaseEndsAt <= state.clock }
                .map(\.id)
                .sorted()
            for runID in dueRunIDs {
                advanceRouteRun(id: runID, state: &state)
            }
            syncRouteRuns(state: &state)

            if nextEventAt.totalMinutes == target.totalMinutes {
                // Route skips and zero-distance legs can schedule another phase
                // at this same minute. Drain those cascades before returning so
                // an otherwise no-op `advance(by: 0)` cannot change the state.
                let hasDueRoutePhase = state.routeRuns.contains { $0.phaseEndsAt <= state.clock }
                if !hasDueRoutePhase { break }
            }
        }

        state.clock = max(state.clock, target)
        chargeFixedCostsIfNeeded(state: &state)
        removeExpiredOffers(state: &state)
        removeExpiredContractOffers(state: &state)
        expireFinishedContracts(state: &state)
    }

    private func advancePhase(of jobID: JobID, state: inout GameState) {
        guard let jobIndex = state.activeJobs.firstIndex(where: { $0.id == jobID }),
              let vehicleIndex = state.vehicles.firstIndex(where: { $0.id == state.activeJobs[jobIndex].vehicleID }),
              let vehicleType = catalog.vehicleType(state.vehicles[vehicleIndex].typeID) else {
            assertionFailure("active job with dangling references")
            return
        }
        var job = state.activeJobs[jobIndex]
        let phaseEnd = job.phaseEndsAt

        switch job.phase {
        case .deadheading:
            state.vehicles[vehicleIndex].cityID = job.offer.origin
            state.vehicles[vehicleIndex].odometerKm += job.deadheadKm
            job.phase = .loading
            job.phaseStartedAt = phaseEnd
            job.phaseEndsAt = phaseEnd + loadingMinutes(at: job.offer.origin)
            state.activeJobs[jobIndex] = job

        case .loading:
            job.phase = .enRoute
            job.phaseStartedAt = phaseEnd
            job.phaseEndsAt = phaseEnd + travelMinutes(distanceKm: job.offer.distanceKm, speedKmh: vehicleType.speedKmh)
            state.activeJobs[jobIndex] = job
            state.appendLog(.jobPickedUp(
                jobID: job.id,
                origin: job.offer.origin,
                destination: job.offer.destination
            ))

        case .enRoute:
            state.vehicles[vehicleIndex].cityID = job.offer.destination
            state.vehicles[vehicleIndex].odometerKm += job.offer.distanceKm
            job.phase = .unloading
            job.phaseStartedAt = phaseEnd
            job.phaseEndsAt = phaseEnd + unloadingMinutes(at: job.offer.destination)
            state.activeJobs[jobIndex] = job

        case .unloading:
            let totalKm = job.deadheadKm + job.offer.distanceKm
            let taskMinutes = job.startedAt.minutes(until: phaseEnd)
            let cost = taskCost(
                totalKm: totalKm,
                taskMinutes: taskMinutes,
                vehicleType: vehicleType
            )
            state.cash += job.offer.payout - cost
            state.stats.deliveredJobs += 1
            state.stats.totalRevenue += job.offer.payout
            state.stats.totalCost += cost
            if let contractID = job.offer.contractID,
               let contractIndex = state.activeContracts.firstIndex(where: { $0.id == contractID }) {
                state.activeContracts[contractIndex].shipmentsCompleted += 1
            }
            state.appendLog(.jobDelivered(
                jobID: job.id,
                destination: job.offer.destination,
                revenue: job.offer.payout,
                cost: cost
            ))
            state.vehicles[vehicleIndex].assignedJobID = nil
            state.activeJobs.remove(at: jobIndex)
        }
    }

    func travelMinutes(distanceKm: Double, speedKmh: Double) -> Int {
        max(1, Int((distanceKm / speedKmh * 60).rounded()))
    }

    /// Loading time scaled by the origin city's urban congestion.
    func loadingMinutes(at city: CityID) -> Int {
        trafficScaled(catalog.economy.loadingMinutes, city: city)
    }

    /// Unloading time scaled by the destination city's urban congestion.
    func unloadingMinutes(at city: CityID) -> Int {
        trafficScaled(catalog.economy.unloadingMinutes, city: city)
    }

    private func trafficScaled(_ baseMinutes: Int, city: CityID) -> Int {
        let index = catalog.city(city)?.trafficDelayIndex ?? 1000
        return max(1, Int((Double(baseMinutes) * Double(index) / 1000).rounded()))
    }

    /// Regional price level of a lane: average endpoint cost index, 1.0 = baseline.
    /// High-cost markets (NY, LA) pay more per km than low-cost ones.
    func lanePriceFactor(origin: CityID, destination: CityID) -> Double {
        let originIndex = catalog.city(origin)?.costIndex ?? 1000
        let destinationIndex = catalog.city(destination)?.costIndex ?? 1000
        return Double(Int(originIndex) + Int(destinationIndex)) / 2000
    }

    func taskCost(totalKm: Double, taskMinutes: Int, vehicleType: VehicleTypeDefinition) -> Money {
        let distanceCost = totalKm * vehicleType.costPerKm
        let driverCost = Double(taskMinutes) / 60 * vehicleType.driverCostPerHour
        return Money((distanceCost + driverCost).rounded())
    }

    /// True cost of hauling a load one way with a given vehicle class: fuel,
    /// wear, wages and the vehicle's own ownership cost for the hours it is
    /// busy. This is the number a payout has to beat to be worth taking.
    func haulCost(
        origin: CityID,
        destination: CityID,
        distanceKm: Double,
        vehicleType: VehicleTypeDefinition
    ) -> (cost: Money, minutes: Int) {
        let minutes = loadingMinutes(at: origin)
            + travelMinutes(distanceKm: distanceKm, speedKmh: vehicleType.speedKmh)
            + unloadingMinutes(at: destination)
        let running = taskCost(totalKm: distanceKm, taskMinutes: minutes, vehicleType: vehicleType)
        let ownership = vehicleType.fixedCostPerDay * Double(minutes) / Double(GameState.minutesPerDay)
        return (running + Money(ownership.rounded()), minutes)
    }

    /// Market price of a haul, built up from what the job actually costs the
    /// class it is sized for.
    ///
    /// It used to be `freightRatePerKm × km`, a rate attached to the *vehicle
    /// type*. That quietly broke the moment the reference class and the class
    /// the player actually assigned differed — most visibly on turn one, where
    /// offers were priced for the cheapest affordable van and then hauled by
    /// the box truck the player had just bought, at a guaranteed loss. The same
    /// disconnect produced the opposite extreme (wildly profitable jobs) when
    /// it fell the other way. Pricing from cost removes the whole class of bug:
    /// a job sized for a class is always worth taking with that class, and the
    /// spread now comes from urgency, region and how full the trailer is —
    /// things the player can read and act on.
    /// Price = the haul's true cost, plus a margin the market conditions size.
    ///
    /// The separation is the whole point. Cost recovery is never scaled:
    /// diesel, wages and the truck's day do not get cheaper because a shipper
    /// is relaxed about timing or the region is cheap. Urgency, regional price
    /// level, how full the trailer is and the company's local presence all move
    /// the *margin*, and since every one of them is a positive multiplier, the
    /// price is cost plus something positive by construction — no clamp holding
    /// it up. That structure is also what gives the spread its shape: a bored
    /// shipper in a cheap market with a half-empty trailer pays a thin margin,
    /// an urgent load in an expensive market on a full trailer pays a fat one.
    func freightPayout(
        origin: CityID,
        destination: CityID,
        distanceKm: Double,
        load: LoadSize,
        vehicleType: VehicleTypeDefinition,
        urgencyMultiplier: Double,
        state: GameState
    ) -> Money {
        let base = haulCost(
            origin: origin,
            destination: destination,
            distanceKm: distanceKm,
            vehicleType: vehicleType
        ).cost

        // Fuller trailers earn a better margin — the reward for loading well.
        let utilisation = util(load: load, capacity: vehicleType.capacity)
        let fillFactor = catalog.economy.fillFloor + (1 - catalog.economy.fillFloor) * utilisation
        // Home-field advantage, finally applied: it was computed and thrown
        // away before, which is why HQ lanes never felt any different.
        let localPresence = lanePremiumFactor(origin: origin, destination: destination, state: state)

        let margin = Double(catalog.economy.spotMarginPercent) / 100
            * urgencyMultiplier
            * lanePriceFactor(origin: origin, destination: destination)
            * fillFactor
            * localPresence

        return Money(max(1, (Double(base) * (1 + margin)).rounded()))
    }

    func util(load: LoadSize, capacity: LoadSize) -> Double {
        let massUtil = capacity.massKg > 0 ? Double(load.massKg) / Double(capacity.massKg) : 0
        let volumeUtil = capacity.volumeM3 > 0 ? load.volumeM3 / capacity.volumeM3 : 0
        return min(1, max(massUtil, volumeUtil))
    }

    // MARK: - Fixed ownership costs

    private func chargeFixedCostsIfNeeded(state: inout GameState) {
        let currentDay = state.clock.totalMinutes / GameState.minutesPerDay
        let days = currentDay - state.lastFixedCostDay
        // Facilities keep costing money even with no fleet: an idle warehouse
        // bleeding upkeep is exactly the pressure the expansion decision needs.
        let hasStandingCosts = !state.vehicles.isEmpty
            || state.facilities.contains { !$0.isHeadquarters }
        guard days > 0, hasStandingCosts else {
            state.lastFixedCostDay = max(state.lastFixedCostDay, currentDay)
            return
        }
        var dailyTotal = 0.0
        for vehicle in state.vehicles {
            if let type = catalog.vehicleType(vehicle.typeID) {
                dailyTotal += type.fixedCostPerDay
            }
        }
        // Under-construction facilities already pay their way: upkeep starts
        // when the site does, matching how a real lease begins at handover.
        for facility in state.facilities where facility.isOperational(at: state.clock) {
            guard let quote = quote(kind: facility.kind, level: facility.level, city: facility.cityID)
            else { continue }
            dailyTotal += Double(quote.upkeepPerDay)
        }
        let charge = Money((dailyTotal * Double(days)).rounded())
        state.cash -= charge
        state.stats.totalCost += charge
        state.lastFixedCostDay = currentDay
    }

    // MARK: - Spot offer generation

    private func removeExpiredOffers(state: inout GameState) {
        let expired = state.offers.filter { $0.expiresAt <= state.clock }
        guard !expired.isEmpty else { return }
        state.offers.removeAll { $0.expiresAt <= state.clock }
        // Contract shipments are obligations: missing the deadline costs compensation.
        for offer in expired where offer.source == .contract {
            chargeMissedShipment(offer: offer, state: &state)
        }
    }

    private func chargeMissedShipment(offer: JobOffer, state: inout GameState) {
        guard let contractID = offer.contractID else { return }
        let percent = Double(catalog.economy.contractPenaltyPercent) / 100
        let penalty = Money(max(0, (Double(offer.payout) * percent).rounded()))
        state.cash -= penalty
        state.stats.totalCost += penalty
        if let index = state.activeContracts.firstIndex(where: { $0.id == contractID }) {
            state.activeContracts[index].shipmentsMissed += 1
            state.activeContracts[index].penaltiesPaid += penalty
        }
        state.appendLog(.contractShipmentMissed(contractID: contractID, penalty: penalty))
    }

    private func removeExpiredContractOffers(state: inout GameState) {
        state.contractOffers.removeAll { $0.expiresAt <= state.clock }
    }

    /// Guarantees that anywhere the player has a truck standing free, there is
    /// something to haul. The timed batch alone was not enough: deliver a load
    /// into a city and the local board is empty by definition — the freight
    /// that was there is the freight you just moved — so the driver sat until
    /// the next batch tick burning a day of fixed costs. Freight appears where
    /// capacity appears, which is also how a real market behaves.
    private func ensureLocalSpotOffers(state: inout GameState) {
        var idleCities: [CityID: [VehicleTypeDefinition]] = [:]
        for vehicle in state.vehicles where state.isVehicleIdle(vehicle.id) {
            guard let type = catalog.vehicleType(vehicle.typeID) else { continue }
            idleCities[vehicle.cityID, default: []].append(type)
        }
        guard !idleCities.isEmpty else { return }

        for origin in idleCities.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let open = state.offers.count { $0.origin == origin && $0.source == .spot }
            guard open == 0, let types = idleCities[origin], !types.isEmpty else { continue }

            // Seeded on the arrival minute so the same campaign replays the
            // same freight; one offer per empty board, not a flood.
            var rng = SeededRNG(seed: SeedDerivation.seed(
                state.config.seed,
                "local_spot",
                .string(origin.rawValue),
                .int(state.clock.totalMinutes)
            ))
            guard let referenceType = types.randomElement(using: &rng),
                  let offer = makeSpotOffer(
                    origin: origin,
                    referenceType: referenceType,
                    generatedAt: state.clock,
                    rng: &rng,
                    state: &state
                  ) else { continue }
            state.offers.append(offer)
        }
    }

    private func generateOfferBatch(state: inout GameState) {
        let batchIndex = state.nextOfferBatchAt.totalMinutes / catalog.economy.offerGenerationIntervalMinutes
        let generatedAt = state.nextOfferBatchAt
        state.nextOfferBatchAt = generatedAt + catalog.economy.offerGenerationIntervalMinutes

        var vehicleTypesByOrigin: [CityID: [VehicleTypeDefinition]] = [:]
        for vehicle in state.vehicles where state.isVehicleIdle(vehicle.id) {
            if let vehicleType = catalog.vehicleType(vehicle.typeID) {
                vehicleTypesByOrigin[vehicle.cityID, default: []].append(vehicleType)
            }
        }
        if state.vehicles.isEmpty,
           let entryVehicleType = catalog.vehicleTypes
            .filter({ $0.purchasePrice <= state.cash })
            .min(by: {
                $0.purchasePrice == $1.purchasePrice
                    ? $0.id.rawValue < $1.id.rawValue
                    : $0.purchasePrice < $1.purchasePrice
            }) {
            vehicleTypesByOrigin[state.config.hqCity] = [entryVehicleType]
        }

        for origin in vehicleTypesByOrigin.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let referenceTypes = vehicleTypesByOrigin[origin], !referenceTypes.isEmpty else { continue }
            let openCount = state.offers.count { $0.origin == origin && $0.source == .spot }
            let availableSlots = offerSlots(for: origin) - openCount
            guard availableSlots > 0 else { continue }

            for slot in 0..<availableSlots {
                var rng = SeededRNG(seed: SeedDerivation.seed(
                    state.config.seed, "offer_batch", .int(batchIndex),
                    .string(origin.rawValue), .int(slot)
                ))
                let guaranteesLocalChoice = openCount == 0 && slot == 0
                guard guaranteesLocalChoice
                        || Int.random(in: 0..<100, using: &rng) < catalog.economy.offerChancePercent else {
                    continue
                }
                guard let referenceType = referenceTypes.randomElement(using: &rng),
                      let offer = makeSpotOffer(
                        origin: origin,
                        referenceType: referenceType,
                        generatedAt: generatedAt,
                        rng: &rng,
                        state: &state
                      ) else {
                    continue
                }
                state.offers.append(offer)
            }
        }
    }

    /// Bigger freight markets sustain more simultaneous open offers.
    private func offerSlots(for city: CityID) -> Int {
        let population = catalog.city(city)?.population ?? 0
        let populationSlots = 1 + population / catalog.economy.offerSlotPopulation
        return min(catalog.economy.maxOpenOffersPerCity, max(1, populationSlots))
    }

    private func makeSpotOffer(
        origin: CityID,
        referenceType: VehicleTypeDefinition,
        generatedAt: GameTime,
        rng: inout SeededRNG,
        state: inout GameState
    ) -> JobOffer? {
        guard let product = pickSuppliedProduct(origin: origin, referenceType: referenceType, rng: &rng),
              let destination = pickDemandingDestination(
                origin: origin,
                productID: product.id,
                preferShort: true,
                rng: &rng
              ) ?? pickDemandingDestination(
                origin: origin,
                productID: product.id,
                preferShort: false,
                rng: &rng
              ),
              let route = catalog.shortestRoute(from: origin, to: destination) else {
            return nil
        }

        let load = makeLoad(
            product: product,
            capacity: referenceType.capacity,
            preferHighFill: true,
            rng: &rng
        )
        guard let load else { return nil }

        let tier = pickUrgencyTier(rng: &rng)
        let urgency = JobUrgency(rawValue: tier.id) ?? .normal
        let payout = freightPayout(
            origin: origin,
            destination: destination,
            distanceKm: route.distanceKm,
            load: load,
            vehicleType: referenceType,
            urgencyMultiplier: tier.multiplier,
            state: state
        )

        return JobOffer(
            id: JobID(rawValue: state.issueID()),
            origin: origin,
            destination: destination,
            productID: product.id,
            load: load,
            payout: payout,
            distanceKm: route.distanceKm,
            urgency: urgency,
            source: .spot,
            contractID: nil,
            originFirmID: catalog.supplierFirm(city: origin, product: product.id)?.id,
            destinationFirmID: catalog.receiverFirm(city: destination, product: product.id)?.id,
            createdAt: generatedAt,
            expiresAt: generatedAt + tier.lifetimeMinutes
        )
    }

    // MARK: - Market-aware selection

    private func pickSuppliedProduct(
        origin: CityID,
        referenceType: VehicleTypeDefinition,
        rng: inout SeededRNG
    ) -> ProductDefinition? {
        let supply = catalog.cityMarket(origin)?.supply ?? []
        let candidates: [(ProductDefinition, UInt16)] = supply.compactMap { entry in
            guard let product = catalog.product(entry.productID),
                  productFits(product, in: referenceType.capacity) else { return nil }
            return (product, entry.weight)
        }
        if let picked = weightedPick(candidates, rng: &rng) {
            return picked
        }
        // Fallback: any product that fits the vehicle.
        let fallback = catalog.products.filter { productFits($0, in: referenceType.capacity) }
        return fallback.randomElement(using: &rng)
    }

    private func pickDemandingDestination(
        origin: CityID,
        productID: ProductID,
        preferShort: Bool,
        rng: inout SeededRNG
    ) -> CityID? {
        var weighted: [(CityID, Double)] = []
        for city in catalog.cities where city.id != origin {
            let demandWeight = Double(
                catalog.cityMarket(city.id)?.demand.first(where: { $0.productID == productID })?.weight ?? 0
            )
            guard demandWeight > 0,
                  let route = catalog.shortestRoute(from: origin, to: city.id) else { continue }
            let distanceWeight = preferShort
                ? 1.0 / pow(max(route.distanceKm, 80), 0.85)
                : pow(max(route.distanceKm, 80), 0.35) / 1000
            weighted.append((city.id, demandWeight * distanceWeight * populationPull(of: city)))
        }
        if weighted.isEmpty {
            // No market match: fall back to distance-weighted reachable cities.
            for city in catalog.cities where city.id != origin {
                guard let route = catalog.shortestRoute(from: origin, to: city.id) else { continue }
                let w = preferShort
                    ? 1.0 / pow(max(route.distanceKm, 80), 0.85)
                    : pow(max(route.distanceKm, 80), 0.35) / 1000
                weighted.append((city.id, w * populationPull(of: city)))
            }
        }
        return weightedPick(weighted, rng: &rng)
    }

    /// Mild attraction toward large consumer markets (fourth-root of millions).
    private func populationPull(of city: CityDefinition) -> Double {
        pow(max(0.25, Double(city.population) / 1_000_000), 0.25)
    }

    private func productFits(_ product: ProductDefinition, in capacity: LoadSize) -> Bool {
        let massStepKg = ProductDefinition.shipmentMassStepKg
        let minimumUnits = product.minimumShipmentMassKg / massStepKg
            + (product.minimumShipmentMassKg % massStepKg == 0 ? 0 : 1)
        let volumeLimitedMassKg = Int(
            (capacity.volumeM3 / product.densityM3PerTon * 1000).rounded(.down)
        )
        let maximumMassKg = min(product.maximumShipmentMassKg, capacity.massKg, volumeLimitedMassKg)
        let maximumUnits = maximumMassKg / massStepKg
        return minimumUnits <= maximumUnits
    }

    private func makeLoad(
        product: ProductDefinition,
        capacity: LoadSize,
        preferHighFill: Bool,
        rng: inout SeededRNG
    ) -> LoadSize? {
        let massStepKg = ProductDefinition.shipmentMassStepKg
        let minimumUnits = product.minimumShipmentMassKg / massStepKg
            + (product.minimumShipmentMassKg % massStepKg == 0 ? 0 : 1)
        let volumeLimitedMassKg = Int(
            (capacity.volumeM3 / product.densityM3PerTon * 1000).rounded(.down)
        )
        let maximumMassKg = min(product.maximumShipmentMassKg, capacity.massKg, volumeLimitedMassKg)
        let maximumUnits = maximumMassKg / massStepKg
        guard minimumUnits <= maximumUnits else { return nil }

        let units: Int
        if preferHighFill, maximumUnits > minimumUnits {
            let mid = (minimumUnits + maximumUnits + 1) / 2
            units = Int.random(in: mid...maximumUnits, using: &rng)
        } else {
            units = Int.random(in: minimumUnits...maximumUnits, using: &rng)
        }
        let massKg = units * massStepKg
        let volumeM3 = (Double(massKg) / 1000 * product.densityM3PerTon * 10).rounded() / 10
        return LoadSize(massKg: massKg, volumeM3: volumeM3)
    }

    private func pickUrgencyTier(rng: inout SeededRNG) -> UrgencyTier {
        let tiers = catalog.economy.urgencyTiers
        let pairs = tiers.map { ($0, Double($0.weight)) }
        return weightedPick(pairs, rng: &rng) ?? tiers[0]
    }

    private func weightedPick<T>(_ items: [(T, Double)], rng: inout SeededRNG) -> T? {
        let total = items.reduce(0.0) { $0 + max(0, $1.1) }
        guard total > 0 else { return items.first?.0 }
        var roll = Double.random(in: 0..<total, using: &rng)
        for (item, weight) in items {
            roll -= max(0, weight)
            if roll < 0 { return item }
        }
        return items.last?.0
    }

    private func weightedPick<T>(_ items: [(T, UInt16)], rng: inout SeededRNG) -> T? {
        weightedPick(items.map { ($0.0, Double($0.1)) }, rng: &rng)
    }

    // MARK: - Contracts

    /// How far the company has grown. Purely derived from state, so it never
    /// needs saving and never drifts. Gates which archetypes the market offers
    /// and how large a cycle volume a customer dares to ask for.
    func companyTier(_ state: GameState) -> Int {
        let vehicles = state.vehicles.count
        let warehouses = state.facilities.filter {
            $0.kind == .warehouse && $0.isOperational(at: state.clock)
        }
        let bigWarehouses = warehouses.filter { $0.level >= 2 }
        if vehicles > 30, !bigWarehouses.isEmpty { return 4 }
        if vehicles >= 11, !warehouses.isEmpty { return 3 }
        if vehicles >= 4 || state.stats.deliveredJobs >= 40 { return 2 }
        return 1
    }

    func archetypes(forTier tier: Int) -> [ContractArchetype] {
        var available: [ContractArchetype] = [.laneRecurring]
        if tier >= 2 { available.append(.evergreen) }
        if tier >= 3 { available.append(.bulkPeriodic) }
        if tier >= 4 { available.append(.multiDrop) }
        return available
    }

    /// How many vehicles' worth of continuous work a customer will hand over at
    /// this scale. Sizing by vehicle-equivalents rather than by parcel count is
    /// what keeps a contract from starving the truck assigned to it: the volume
    /// is derived from the cadence, so a daily short lane asks for several runs
    /// a day instead of one load and 20 idle hours.
    private func vehicleEquivalents(forTier tier: Int) -> Double {
        switch tier {
        case 1: 1
        case 2: 2
        case 3: 6
        default: 20
        }
    }

    /// Target share of the cadence a dedicated vehicle should actually be
    /// driving. Below 1 on purpose: the player needs slack to absorb delays.
    private static let targetUtilization = 0.65


    /// Parcels one cycle should contain so the work fills the cadence.
    private func parcelsPerCycle(
        intervalMinutes: Int,
        cycleMinutes: Int,
        tier: Int,
        dropCount: Int
    ) -> Int {
        guard cycleMinutes > 0 else { return 1 }
        let capacity = Double(intervalMinutes) * Self.targetUtilization
            * vehicleEquivalents(forTier: tier) / Double(cycleMinutes)
        // Every destination needs at least one parcel or the split is a lie.
        return max(dropCount, min(60, Int(capacity.rounded())))
    }

    /// How many contract lanes one branch city keeps on the table. Contracts
    /// are not a scarcity game — the scarce thing is the branch investment, so
    /// a branch city always shows a workable menu, scaled by its own market.
    func contractSlots(in cityID: CityID, state: GameState) -> Int {
        guard let city = catalog.city(cityID),
              let branch = state.branch(in: cityID),
              branch.isOperational(at: state.clock),
              let quote = quote(kind: .branch, level: branch.level, city: cityID) else { return 0 }
        let insight = CityInsight.make(city: city, catalog: catalog)
        let base = 3 + 6 * insight.marketSizePercent
        return max(2, Int((base * quote.contractSlotFactor).rounded()))
    }

    /// Contract margin for a lane out of this city. Big markets pay better;
    /// crowded markets squeeze. One formula, so competitors later change only
    /// `competitionPercent` and every price follows.
    func contractMargin(origin: CityID, destination: CityID) -> Double {
        let base = Double(catalog.economy.contractMarginPercent) / 100
        guard let city = catalog.city(origin) else { return base }
        let insight = CityInsight.make(city: city, catalog: catalog)
        let demandBonus = 1 + 0.35 * insight.marketSizePercent
        let competitionSqueeze = 1 - 0.30 * insight.competitionPercent
        return base * demandBonus * competitionSqueeze
            * lanePriceFactor(origin: origin, destination: destination)
    }

    /// Advances the batch clock. The board refill itself is not tied to this
    /// tick — see `replenishContractOffers`.
    private func generateContractOfferBatch(state: inout GameState) {
        state.nextContractBatchAt = state.nextContractBatchAt
            + catalog.economy.contractOfferIntervalMinutes
        replenishContractOffers(state: &state)
    }

    /// Refills every branch city's contract board to its slot count. Runs on
    /// the event loop rather than only on the daily tick, so signing a lane or
    /// a batch of offers ageing out cannot leave a branch showing an empty
    /// board until the next morning.
    private func replenishContractOffers(state: inout GameState) {
        let interval = catalog.economy.contractOfferIntervalMinutes
        // One generation attempt per slot per interval keeps the board stocked
        // without minting a fresh lane every simulated minute.
        let batchIndex = state.clock.totalMinutes / max(1, interval)
        let generatedAt = state.clock

        let referenceTypes: [VehicleTypeDefinition] = {
            let owned = state.vehicles.compactMap { catalog.vehicleType($0.typeID) }
            if !owned.isEmpty { return owned }
            if let entry = catalog.vehicleTypes
                .filter({ $0.purchasePrice <= state.cash })
                .min(by: { $0.purchasePrice < $1.purchasePrice }) {
                return [entry]
            }
            return Array(catalog.vehicleTypes.prefix(1))
        }()
        guard !referenceTypes.isEmpty else { return }

        // Shippers do not hand recurring volume to a company that has never
        // moved anything. The first days are spot work; contracts are what the
        // player graduates into once they have proven they can deliver.
        guard state.stats.deliveredJobs >= catalog.economy.contractsUnlockAfterDeliveries else { return }

        let tier = companyTier(state)
        let available = archetypes(forTier: tier)

        // Contract business exists only where the company has a branch, and a
        // branch city's board is never allowed to sit empty: whatever emptied
        // it — expiry, signing, a demolished rival branch — the next pass tops
        // it straight back up. Having a branch *is* the standing entitlement to
        // see work, independent of where the fleet happens to be parked.
        for origin in state.contractCities.sorted(by: { $0.rawValue < $1.rawValue }) {
            let slots = contractSlots(in: origin, state: state)
            let open = state.contractOffers.count { $0.origin == origin }
            guard open < slots else { continue }

            for slot in open..<slots {
                var rng = SeededRNG(seed: SeedDerivation.seed(
                    state.config.seed,
                    "contract_batch",
                    .int(batchIndex),
                    .string(origin.rawValue),
                    .int(slot)
                ))
                guard let referenceType = referenceTypes.randomElement(using: &rng),
                      let archetype = available.randomElement(using: &rng),
                      let offer = makeContractOffer(
                        archetype: archetype,
                        origin: origin,
                        referenceType: referenceType,
                        tier: tier,
                        generatedAt: generatedAt,
                        state: &state,
                        rng: &rng
                      ) else { continue }
                state.contractOffers.append(offer)
            }
        }
    }

    private func makeContractOffer(
        archetype: ContractArchetype,
        origin: CityID,
        referenceType: VehicleTypeDefinition,
        tier: Int,
        generatedAt: GameTime,
        state: inout GameState,
        rng: inout SeededRNG
    ) -> ContractOffer? {
        guard let product = pickSuppliedProduct(origin: origin, referenceType: referenceType, rng: &rng),
              let parcel = makeLoad(
                product: product,
                capacity: referenceType.capacity,
                preferHighFill: true,
                rng: &rng
              ) else { return nil }

        // How many delivery points this customer needs served.
        let dropCount = archetype == .multiDrop ? Int.random(in: 2...3, using: &rng) : 1
        var chosen: [CityID] = []
        for _ in 0..<dropCount {
            guard let city = pickDemandingDestination(
                origin: origin,
                productID: product.id,
                preferShort: Bool.random(using: &rng),
                rng: &rng
            ), !chosen.contains(city) else { continue }
            chosen.append(city)
        }
        guard !chosen.isEmpty else { return nil }

        // Price and size each destination on its own cycle.
        struct Leg {
            let cityID: CityID
            let distanceKm: Double
            let cycleMinutes: Int
            let cycleCost: Money
        }
        var legs: [Leg] = []
        for cityID in chosen {
            guard let route = catalog.shortestRoute(from: origin, to: cityID) else { continue }
            let cycleMinutes = contractCycleMinutes(
                origin: origin,
                destination: cityID,
                distanceKm: route.distanceKm,
                vehicleType: referenceType
            )
            legs.append(Leg(
                cityID: cityID,
                distanceKm: route.distanceKm,
                cycleMinutes: cycleMinutes,
                cycleCost: contractCycleCost(
                    origin: origin,
                    destination: cityID,
                    distanceKm: route.distanceKm,
                    cycleMinutes: cycleMinutes,
                    vehicleType: referenceType
                )
            ))
        }
        guard !legs.isEmpty else { return nil }
        let longestCycleMinutes = legs.map(\.cycleMinutes).max() ?? 0
        guard longestCycleMinutes > 0 else { return nil }

        // Cadence first, then volume derived from it. Sizing this way is what
        // keeps a dedicated vehicle busy: a short lane on a daily rhythm asks
        // for several runs a day, not one load and twenty idle hours.
        let interval = shipmentInterval(
            archetype: archetype,
            cycleMinutes: longestCycleMinutes,
            rng: &rng
        )
        let parcels = parcelsPerCycle(
            intervalMinutes: interval,
            cycleMinutes: longestCycleMinutes,
            tier: tier,
            dropCount: legs.count
        )
        let volumePerCycleKg = parcel.massKg * parcels

        // Shares are whole basis points and must total exactly 10 000, so the
        // posted volume never silently drifts from the agreed volume.
        let even = ContractDestination.fullShareBps / legs.count
        let destinations = legs.enumerated().map { index, leg in
            let margin = contractMargin(origin: origin, destination: leg.cityID)
            return ContractDestination(
                cityID: leg.cityID,
                firmID: catalog.receiverFirm(city: leg.cityID, product: product.id)?.id,
                shareBps: index == 0
                    ? even + (ContractDestination.fullShareBps - even * legs.count)
                    : even,
                distanceKm: leg.distanceKm,
                payoutPerParcel: Money(max(1, (Double(leg.cycleCost) * (1 + margin)).rounded()))
            )
        }

        return ContractOffer(
            id: ContractID(rawValue: state.issueID()),
            origin: origin,
            productID: product.id,
            archetype: archetype,
            destinations: destinations,
            referenceVehicleTypeID: referenceType.id,
            parcelMassKg: parcel.massKg,
            volumePerCycleKg: volumePerCycleKg,
            shipmentIntervalMinutes: interval,
            deliveryWindowMinutes: deliveryWindow(cycleMinutes: longestCycleMinutes, interval: interval),
            leadTimeMinutes: leadTime(cycleMinutes: longestCycleMinutes),
            durationDays: contractDuration(archetype: archetype, rng: &rng),
            originFirmID: catalog.supplierFirm(city: origin, product: product.id)?.id,
            createdAt: generatedAt,
            // Staggered on purpose. Topping the board up to N means one cohort
            // is created together, and a fixed lifetime would then retire the
            // whole board in the same minute — which is exactly the "all the
            // contracts vanished at once" the branch screen was showing. Random
            // lifetimes turn that cliff into steady rotation.
            expiresAt: generatedAt
                + catalog.economy.contractOfferIntervalMinutes * Int.random(in: 2...6, using: &rng)
        )
    }

    /// Cadence between posted cycles, always a whole number of days so the
    /// player can plan around a readable rhythm.
    private func shipmentInterval(
        archetype: ContractArchetype,
        cycleMinutes: Int,
        rng: inout SeededRNG
    ) -> Int {
        // Never tighter than one cycle: a cadence the reference vehicle cannot
        // physically meet is a trap, not a challenge.
        let minimumDays = max(1, (cycleMinutes + GameState.minutesPerDay - 1) / GameState.minutesPerDay)
        let days: Int = switch archetype {
        case .laneRecurring, .evergreen:
            minimumDays + Int.random(in: 0...1, using: &rng)
        case .multiDrop:
            max(2, minimumDays + Int.random(in: 1...2, using: &rng))
        case .bulkPeriodic:
            // Weekly or fortnightly drumbeat: enough runway to stage a fleet.
            max(minimumDays, Int.random(in: 7...14, using: &rng))
        }
        return days * GameState.minutesPerDay
    }

    /// Time a posted parcel has before it counts as late. Deliberately not the
    /// shipment interval: a daily lane over 800 km would be impossible to serve.
    func deliveryWindow(cycleMinutes: Int, interval: Int) -> Int {
        let fromCycle = Int(
            Double(cycleMinutes) * Double(catalog.economy.contractDeliveryWindowPercent) / 100
        )
        let floor = Int(
            Double(interval) * Double(catalog.economy.contractDeliveryWindowFloorPercent) / 100
        )
        return max(60, max(fromCycle, floor))
    }

    /// Preparation time between signing and the first posted cycle, so the
    /// player can position vehicles instead of being caught mid-network.
    func leadTime(cycleMinutes: Int) -> Int {
        max(60, Int(Double(cycleMinutes) * Double(catalog.economy.contractLeadTimePercent) / 100))
    }

    private func contractDuration(archetype: ContractArchetype, rng: inout SeededRNG) -> Int? {
        switch archetype {
        case .evergreen:
            return nil
        case .laneRecurring:
            return catalog.economy.contractDurationDays * Int.random(in: 1...3, using: &rng)
        case .multiDrop, .bulkPeriodic:
            return catalog.economy.contractDurationDays * Int.random(in: 2...6, using: &rng)
        }
    }

    private func postDueContractShipments(state: inout GameState) {
        for index in state.activeContracts.indices {
            while state.activeContracts[index].nextShipmentAt <= state.clock,
                  !state.activeContracts[index].isClosing(at: state.clock) {
                postContractCycle(contractIndex: index, state: &state)
            }
        }
    }

    /// True cost of running one cycle for a customer. The trip cost alone was
    /// never the real cost: owning the vehicle is charged every day whether it
    /// rolls or not, so a quote that ignores it under-prices every contract and
    /// makes short lanes structurally unprofitable. Charged as the cycle's fair
    /// share of a day, grossed up by the utilisation the lane can realistically
    /// reach — a player who packs the truck better keeps the difference.
    func contractCycleCost(
        origin: CityID,
        destination: CityID,
        distanceKm: Double,
        cycleMinutes: Int,
        vehicleType: VehicleTypeDefinition
    ) -> Money {
        let tripCost = taskCost(
            totalKm: distanceKm * 2,
            taskMinutes: cycleMinutes,
            vehicleType: vehicleType
        )
        let dayShare = Double(cycleMinutes) / Double(GameState.minutesPerDay)
        let ownership = vehicleType.fixedCostPerDay * dayShare / Self.targetUtilization
        return tripCost + Money(ownership.rounded())
    }

    /// Minutes for one full contract cycle with the given vehicle class:
    /// load at origin, drive loaded, unload at destination, drive back empty.
    func contractCycleMinutes(
        origin: CityID,
        destination: CityID,
        distanceKm: Double,
        vehicleType: VehicleTypeDefinition
    ) -> Int {
        let oneWay = travelMinutes(distanceKm: distanceKm, speedKmh: vehicleType.speedKmh)
        return loadingMinutes(at: origin) + oneWay + unloadingMinutes(at: destination) + oneWay
    }

    /// Posts one full cycle: the agreed volume split into vehicle-sized parcels
    /// across every destination. A bulk contract posts many parcels at once —
    /// that is precisely the pressure that makes a hub network worth building.
    private func postContractCycle(contractIndex: Int, state: inout GameState) {
        guard state.activeContracts.indices.contains(contractIndex) else { return }
        var contract = state.activeContracts[contractIndex]
        guard !contract.isClosing(at: state.clock) else { return }

        let deadline = state.clock + contract.deliveryWindowMinutes
        for destination in contract.destinations {
            var remaining = contract.cycleVolume(for: destination)
            while remaining > 0 {
                let massKg = min(remaining, contract.parcelMassKg)
                remaining -= massKg
                // Partial parcels pay pro rata: half a load earns half the fee.
                let payout = contract.parcelMassKg > 0
                    ? Money(
                        (Double(destination.payoutPerParcel) * Double(massKg)
                            / Double(contract.parcelMassKg)).rounded()
                      )
                    : destination.payoutPerParcel
                state.offers.append(JobOffer(
                    id: JobID(rawValue: state.issueID()),
                    origin: contract.origin,
                    destination: destination.cityID,
                    productID: contract.productID,
                    load: parcelLoad(productID: contract.productID, massKg: massKg),
                    payout: max(1, payout),
                    distanceKm: destination.distanceKm,
                    urgency: .normal,
                    source: .contract,
                    contractID: contract.id,
                    originFirmID: contract.originFirmID,
                    destinationFirmID: destination.firmID,
                    createdAt: state.clock,
                    expiresAt: deadline
                ))
                contract.shipmentsIssued += 1
            }
        }
        contract.nextShipmentAt = contract.nextShipmentAt + contract.shipmentIntervalMinutes
        state.activeContracts[contractIndex] = contract
    }

    /// Volume of a parcel derived from the product's density.
    func parcelLoad(productID: ProductID, massKg: Int) -> LoadSize {
        let density = catalog.product(productID)?.densityM3PerTon ?? 1
        let volumeM3 = (Double(massKg) / 1000 * density * 10).rounded() / 10
        return LoadSize(massKg: massKg, volumeM3: volumeM3)
    }

    // MARK: - Route commands

    private func createRoute(name: String, state: inout GameState) {
        let resolved = name.isEmpty ? "Route \(state.routes.count + 1)" : name
        state.routes.append(Route(
            id: RouteID(rawValue: state.issueID()),
            name: resolved,
            contractID: nil,
            stops: [],
            vehicleIDs: [],
            isRunning: false
        ))
    }

    private func renameRoute(_ routeID: RouteID, name: String, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        guard !name.isEmpty else { return }
        state.routes[index].name = name
    }

    private func addTravelStop(routeID: RouteID, cityID: CityID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }),
              catalog.city(cityID) != nil else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        // Appending never disturbs running stop indices, so it is always allowed.
        state.routes[index].stops.append(
            RouteStop(id: state.issueID(), cityID: cityID, task: .travel)
        )
    }

    /// Structural edits require a fully stopped route (no runs referencing indices).
    private func editableRouteIndex(_ routeID: RouteID, state: GameState) throws -> Int {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil,
              !state.routes[index].isRunning,
              state.routeRuns(of: routeID).isEmpty else {
            throw CommandError.routeIsRunning
        }
        return index
    }

    private func removeRouteStop(routeID: RouteID, stopID: Int, state: inout GameState) throws {
        let index = try editableRouteIndex(routeID, state: state)
        guard let stop = state.routes[index].stops.first(where: { $0.id == stopID }) else {
            throw CommandError.unknownReference
        }
        switch stop.task {
        case .pickupShipment(let jobID), .deliverShipment(let jobID):
            // Shipment stops travel in pairs; go through the job detach path.
            try removeJobFromRoute(jobID: jobID, routeID: routeID, state: &state)
        case .travel, .pickupContract, .deliverContract,
             .dropToWarehouse, .loadFromWarehouse, .deliverAll:
            // Standing instructions with no cargo bookkeeping of their own.
            state.routes[index].stops.removeAll { $0.id == stopID }
        }
    }

    private func moveRouteStop(routeID: RouteID, stopID: Int, offset: Int, state: inout GameState) throws {
        let index = try editableRouteIndex(routeID, state: state)
        guard let position = state.routes[index].stops.firstIndex(where: { $0.id == stopID }) else {
            throw CommandError.unknownReference
        }
        let target = position + (offset < 0 ? -1 : 1)
        guard state.routes[index].stops.indices.contains(target) else { return }
        state.routes[index].stops.swapAt(position, target)
    }

    /// Consecutive stops in the same city form one player-visible visit. The
    /// first stop id is its stable editing id; tasks remain flat so the existing
    /// route runner can execute them without a second hierarchy.
    private func routeVisitBlocks(_ stops: [RouteStop]) -> [[RouteStop]] {
        stops.reduce(into: []) { blocks, stop in
            if let last = blocks.indices.last, blocks[last].last?.cityID == stop.cityID {
                blocks[last].append(stop)
            } else {
                blocks.append([stop])
            }
        }
    }

    private func addContractTaskToRoute(
        routeID: RouteID,
        visitStopID: Int,
        contractID: ContractID,
        action: ContractRouteAction,
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        guard let contract = state.activeContract(contractID) else {
            throw CommandError.unknownReference
        }
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        guard let block = blocks.first(where: { $0.first?.id == visitStopID }),
              let cityID = block.first?.cityID,
              let lastStopID = block.last?.id,
              let insertionIndex = state.routes[routeIndex].stops.firstIndex(where: { $0.id == lastStopID }) else {
            throw CommandError.unknownReference
        }

        let task: RouteTask
        switch action {
        case .pickup:
            guard cityID == contract.origin else { throw CommandError.unknownReference }
            task = .pickupContract(contractID)
        case .deliver:
            // Multi-drop contracts deliver to several cities; any of them is
            // a valid delivery point for this task.
            guard contract.destinations.contains(where: { $0.cityID == cityID }) else {
                throw CommandError.unknownReference
            }
            task = .deliverContract(contractID)
        }

        // Repeated taps are harmless and must not create multiple recurring
        // claims for the same contract action on one route.
        guard !state.routes[routeIndex].stops.contains(where: {
            $0.task == task && $0.cityID == cityID
        }) else { return }
        let stop = RouteStop(id: state.issueID(), cityID: cityID, task: task)
        state.routes[routeIndex].stops.insert(stop, at: insertionIndex + 1)
    }

    /// Adds a warehouse or bulk-delivery action to a city visit. These are the
    /// tasks that turn a point-to-point lane into an actual network.
    private func addNetworkTaskToRoute(
        routeID: RouteID,
        visitStopID: Int,
        task: RouteTask,
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        guard let block = blocks.first(where: { $0.first?.id == visitStopID }),
              let cityID = block.first?.cityID,
              let lastStopID = block.last?.id,
              let insertionIndex = state.routes[routeIndex].stops.firstIndex(where: { $0.id == lastStopID })
        else { throw CommandError.unknownReference }

        switch task {
        case .dropToWarehouse, .loadFromWarehouse:
            // A warehouse task without a warehouse would silently do nothing,
            // which is worse than refusing it up front.
            guard state.warehouse(in: cityID) != nil else { throw CommandError.warehouseRequired }
        case .deliverAll:
            break
        case .travel, .pickupShipment, .deliverShipment, .pickupContract, .deliverContract:
            throw CommandError.unknownReference
        }

        guard !state.routes[routeIndex].stops.contains(where: {
            $0.task == task && $0.cityID == cityID
        }) else { return }
        state.routes[routeIndex].stops.insert(
            RouteStop(id: state.issueID(), cityID: cityID, task: task),
            at: insertionIndex + 1
        )
    }

    private func reorderRouteVisits(
        routeID: RouteID,
        orderedVisitIDs: [Int],
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        let currentIDs = blocks.compactMap { $0.first?.id }
        guard orderedVisitIDs.count == currentIDs.count,
              Set(orderedVisitIDs).count == orderedVisitIDs.count,
              Set(orderedVisitIDs) == Set(currentIDs) else {
            throw CommandError.unknownReference
        }
        let blocksByID = Dictionary(uniqueKeysWithValues: blocks.compactMap { block in
            block.first.map { ($0.id, block) }
        })
        state.routes[routeIndex].stops = orderedVisitIDs.flatMap { blocksByID[$0] ?? [] }
    }

    private func removeRouteVisit(
        routeID: RouteID,
        visitStopID: Int,
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        guard let block = blocks.first(where: { $0.first?.id == visitStopID }) else {
            throw CommandError.unknownReference
        }

        let blockStopIDs = Set(block.map(\.id))
        let boundJobIDs = Set(block.compactMap { stop -> JobID? in
            switch stop.task {
            case .pickupShipment(let jobID), .deliverShipment(let jobID): return jobID
            case .travel, .pickupContract, .deliverContract,
                 .dropToWarehouse, .loadFromWarehouse, .deliverAll: return nil
            }
        })
        let detached = try boundJobIDs.map { jobID -> Shipment in
            guard let shipment = state.shipments.first(where: {
                $0.id == jobID && $0.assignedRouteID == routeID
            }) else {
                throw CommandError.unknownReference
            }
            guard shipment.loadedVehicleID == nil else { throw CommandError.vehicleBusy }
            return shipment
        }.sorted { $0.id.rawValue < $1.id.rawValue }

        state.shipments.removeAll {
            $0.assignedRouteID == routeID && boundJobIDs.contains($0.id)
        }
        state.routes[routeIndex].stops.removeAll { stop in
            if blockStopIDs.contains(stop.id) { return true }
            switch stop.task {
            case .pickupShipment(let jobID), .deliverShipment(let jobID):
                return boundJobIDs.contains(jobID)
            case .travel, .pickupContract, .deliverContract,
                 .dropToWarehouse, .loadFromWarehouse, .deliverAll:
                return false
            }
        }
        for shipment in detached {
            detachShipment(shipment, state: &state)
        }
    }

    /// Accepts a market offer into a route: the cargo starts waiting at its
    /// origin firm address and pickup + delivery stops append to the lap.
    private func addJobToRoute(offerID: JobID, routeID: RouteID, state: inout GameState) throws {
        guard let routeIndex = state.routes.firstIndex(where: { $0.id == routeID }),
              let offerIndex = state.offers.firstIndex(where: { $0.id == offerID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[routeIndex].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        let offer = state.offers[offerIndex]
        guard state.clock < offer.expiresAt else { throw CommandError.offerExpired }

        state.offers.remove(at: offerIndex)
        state.shipments.append(Shipment(
            id: offer.id,
            offer: offer,
            location: .address(offer.origin),
            assignedRouteID: routeID
        ))
        state.routes[routeIndex].stops.append(contentsOf: [
            RouteStop(id: state.issueID(), cityID: offer.origin, task: .pickupShipment(offer.id)),
            RouteStop(id: state.issueID(), cityID: offer.destination, task: .deliverShipment(offer.id))
        ])
        state.appendLog(.jobAccepted(jobID: offer.id, origin: offer.origin, destination: offer.destination))
        syncRouteRuns(state: &state)
    }

    private func removeJobFromRoute(jobID: JobID, routeID: RouteID, state: inout GameState) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        guard let shipmentIndex = state.shipments.firstIndex(where: {
            $0.id == jobID && $0.assignedRouteID == routeID
        }) else {
            throw CommandError.unknownReference
        }
        guard state.shipments[shipmentIndex].loadedVehicleID == nil else {
            throw CommandError.vehicleBusy
        }
        // Cargo already resting in a warehouse is not lost when its route is
        // edited: it simply becomes free stock any other route can claim.
        if state.shipments[shipmentIndex].location.facilityID != nil {
            state.shipments[shipmentIndex].assignedRouteID = nil
            state.routes[routeIndex].stops.removeAll {
                $0.task == .pickupShipment(jobID) || $0.task == .deliverShipment(jobID)
            }
            return
        }
        let shipment = state.shipments.remove(at: shipmentIndex)
        state.routes[routeIndex].stops.removeAll {
            $0.task == .pickupShipment(jobID) || $0.task == .deliverShipment(jobID)
        }
        detachShipment(shipment, state: &state)
    }

    /// Contract obligations return to the market (or settle as missed);
    /// forfeited spot cargo simply disappears without payment.
    private func detachShipment(_ shipment: Shipment, state: inout GameState) {
        guard shipment.offer.contractID != nil else { return }
        if state.clock < shipment.offer.expiresAt {
            state.offers.append(shipment.offer)
        } else {
            chargeMissedShipment(offer: shipment.offer, state: &state)
        }
    }

    private func assignVehicleToRoute(routeID: RouteID, vehicleID: VehicleID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }),
              state.vehicle(vehicleID) != nil else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        guard state.route(of: vehicleID) == nil else { throw CommandError.vehicleAlreadyAssigned }
        state.routes[index].vehicleIDs.append(vehicleID)
        state.appendLog(.vehicleAssignedToRoute(vehicleID: vehicleID, routeID: routeID))
        syncRouteRuns(state: &state)
    }

    private func unassignVehicleFromRoute(routeID: RouteID, vehicleID: VehicleID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }),
              state.routes[index].vehicleIDs.contains(vehicleID) else {
            throw CommandError.unknownReference
        }
        state.routes[index].vehicleIDs.removeAll { $0 == vehicleID }
        if let runIndex = state.routeRuns.firstIndex(where: { $0.vehicleID == vehicleID }) {
            state.routeRuns[runIndex].isWindingDown = true
        }
        state.appendLog(.vehicleUnassignedFromRoute(vehicleID: vehicleID, routeID: routeID))
        syncRouteRuns(state: &state)
    }

    private func startRoute(_ routeID: RouteID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        guard !state.routes[index].isRunning else { return }
        guard !state.routes[index].stops.isEmpty else { throw CommandError.noRoute }
        guard !state.routes[index].vehicleIDs.isEmpty else {
            throw CommandError.noVehicleAssigned
        }
        let pickupContracts = Set(state.routes[index].stops.compactMap { stop -> ContractID? in
            if case .pickupContract(let contractID) = stop.task { return contractID }
            return nil
        })
        let deliveryContracts = Set(state.routes[index].stops.compactMap { stop -> ContractID? in
            if case .deliverContract(let contractID) = stop.task { return contractID }
            return nil
        })
        // Cargo picked up must have somewhere to go on this same lap: either a
        // matching delivery, a warehouse hand-off, or a catch-all delivery stop.
        let hasHandoff = state.routes[index].stops.contains { stop in
            stop.task == .dropToWarehouse || stop.task == .deliverAll
        }
        guard hasHandoff || pickupContracts.isSubset(of: deliveryContracts) else {
            throw CommandError.incompleteRouteTasks
        }
        state.routes[index].isRunning = true
        for runIndex in state.routeRuns.indices where state.routeRuns[runIndex].routeID == routeID {
            state.routeRuns[runIndex].isWindingDown = false
        }
        state.appendLog(.routeStarted(routeID: routeID))
        syncRouteRuns(state: &state)
    }

    private func stopRoute(_ routeID: RouteID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].isRunning else { return }
        state.routes[index].isRunning = false
        for runIndex in state.routeRuns.indices where state.routeRuns[runIndex].routeID == routeID {
            state.routeRuns[runIndex].isWindingDown = true
        }
        state.appendLog(.routeStopped(routeID: routeID))
        syncRouteRuns(state: &state)
    }

    private func deleteRoute(_ routeID: RouteID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        if state.routes[index].cancellationRequestedAt == nil {
            let wasRunning = state.routes[index].isRunning
            state.routes[index].isRunning = false
            state.routes[index].cancellationRequestedAt = state.clock
            for runIndex in state.routeRuns.indices where state.routeRuns[runIndex].routeID == routeID {
                state.routeRuns[runIndex].isWindingDown = true
            }
            if wasRunning {
                state.appendLog(.routeStopped(routeID: routeID))
            }
        }
        syncRouteRuns(state: &state)
    }

    /// A cancelled route remains available to its runners until committed
    /// cargo is delivered. Once the last run releases, waiting cargo is settled
    /// with the same bookkeeping as an ordinary stopped-route deletion.
    private func finalizeCancelledRoutes(state: inout GameState) {
        let ready = state.routes
            .filter {
                $0.cancellationRequestedAt != nil && state.routeRuns(of: $0.id).isEmpty
            }
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
        for routeID in ready {
            purgeRoute(routeID, state: &state)
        }
    }

    private func purgeRoute(_ routeID: RouteID, state: inout GameState) {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else { return }
        // Cargo resting in a warehouse survives its route's deletion — it is
        // physically stored somewhere, so it simply becomes free stock.
        for shipmentIndex in state.shipments.indices
        where state.shipments[shipmentIndex].assignedRouteID == routeID
            && state.shipments[shipmentIndex].location.facilityID != nil {
            state.shipments[shipmentIndex].assignedRouteID = nil
        }
        let orphans = state.shipments
            .filter { $0.assignedRouteID == routeID }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        state.shipments.removeAll { $0.assignedRouteID == routeID }
        for shipment in orphans {
            detachShipment(shipment, state: &state)
        }
        state.routes.remove(at: index)
    }

    // MARK: - Route runner

    /// Distant sentinel for waits with no timer (cargo not due yet).
    private static let waitSentinel = GameTime(totalMinutes: Int.max / 4)
    /// Retry delay when a lap makes no progress or a leg has no road.
    private static let idleRetryMinutes = 60

    /// Spawns runs for idle vehicles on running routes and re-evaluates
    /// sentinel waits. Called from the event loop and route commands.
    private func syncRouteRuns(state: inout GameState) {
        for route in state.routes where route.isRunning && !route.stops.isEmpty {
            for vehicleID in route.vehicleIDs where state.isVehicleIdle(vehicleID) {
                spawnRun(routeID: route.id, vehicleID: vehicleID, state: &state)
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

    private func spawnRun(routeID: RouteID, vehicleID: VehicleID, state: inout GameState) {
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
        applyLeg(&run, from: vehicle.cityID, to: route.stops[0].cityID, vehicleType: vehicleType, clock: state.clock)
        state.routeRuns.append(run)
    }

    /// Fills traveling-phase fields for a leg; falls back to a timed wait when
    /// the road network offers no path.
    private func applyLeg(
        _ run: inout RouteRun,
        from origin: CityID,
        to destination: CityID,
        vehicleType: VehicleTypeDefinition,
        clock: GameTime
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
            run.phaseEndsAt = clock + travelMinutes(distanceKm: leg.distanceKm, speedKmh: vehicleType.speedKmh)
        } else {
            run.phase = .waiting
            run.legDistanceKm = 0
            run.phaseEndsAt = clock + Self.idleRetryMinutes
        }
    }

    private func advanceRouteRun(id: Int, state: inout GameState) {
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
    private func beginService(runID: Int, state: inout GameState) {
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
            run.phase = .servicing
            run.phaseStartedAt = state.clock
            run.phaseEndsAt = state.clock + minutes
            run.claimedShipmentIDs = shipmentIDs
            state.routeRuns[runIndex] = run
        }
        func waitForCargo() {
            run.phase = .waiting
            run.phaseStartedAt = state.clock
            run.phaseEndsAt = Self.waitSentinel
            run.claimedShipmentIDs = []
            state.routeRuns[runIndex] = run
        }
        func skip(loggingJob jobID: JobID? = nil) {
            if let jobID {
                state.appendLog(.routeShipmentSkipped(routeID: route.id, jobID: jobID))
            }
            state.routeRuns[runIndex] = run
            advanceToNextStop(runID: runID, state: &state)
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
                || state.warehouse(in: stop.cityID).map { shipment.location == .warehouse($0.id) } == true
            guard isHere else {
                skip(loggingJob: jobID)
                return
            }
            guard combinedLoad(state.cargoLoad(of: vehicle.id), shipment.offer.load)
                .fits(in: vehicleType.capacity) else {
                skip(loggingJob: jobID)
                return
            }
            startService(minutes: handlingMinutes(loading: true, at: stop.cityID, state: state), claiming: [jobID])

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
                minutes: handlingMinutes(loading: true, at: stop.cityID, state: state),
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
            startService(minutes: handlingMinutes(loading: false, at: stop.cityID, state: state), claiming: [jobID])

        case .deliverContract(let contractID):
            let carried = state.shipments.contains {
                $0.loadedVehicleID == vehicle.id
                    && $0.offer.contractID == contractID
                    && $0.offer.destination == stop.cityID
            }
            guard carried else {
                skip()
                return
            }
            startService(minutes: handlingMinutes(loading: false, at: stop.cityID, state: state))

        case .deliverAll:
            // One distribution run, many customers: everything that belongs
            // to this city comes off here.
            let carried = state.shipments.contains {
                $0.loadedVehicleID == vehicle.id && $0.isDeliverable(at: stop.cityID)
            }
            guard carried else {
                skip()
                return
            }
            startService(minutes: handlingMinutes(loading: false, at: stop.cityID, state: state))

        case .dropToWarehouse:
            guard let warehouse = state.warehouse(in: stop.cityID),
                  warehouse.isOperational(at: state.clock) else {
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
            startService(minutes: handlingMinutes(loading: false, at: stop.cityID, state: state))

        case .loadFromWarehouse(let lotKey):
            guard !run.isWindingDown,
                  let warehouse = state.warehouse(in: stop.cityID),
                  warehouse.isOperational(at: state.clock) else {
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
            startService(minutes: handlingMinutes(loading: true, at: stop.cityID, state: state))
        }
    }

    /// Handling duration at a city, shortened by a well-equipped warehouse.
    func handlingMinutes(loading: Bool, at cityID: CityID, state: GameState) -> Int {
        let base = loading ? loadingMinutes(at: cityID) : unloadingMinutes(at: cityID)
        guard let warehouse = state.warehouse(in: cityID),
              warehouse.isOperational(at: state.clock),
              let quote = quote(kind: .warehouse, level: warehouse.level, city: cityID) else {
            return base
        }
        return max(1, Int((Double(base) * quote.handlingFactor).rounded()))
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
    func freeStorage(of facility: Facility, state: GameState) -> LoadSize {
        guard let quote = quote(kind: .warehouse, level: facility.level, city: facility.cityID) else {
            return LoadSize(massKg: 0, volumeM3: 0)
        }
        let used = state.storedLoad(in: facility.id)
        return LoadSize(
            massKg: max(0, quote.storage.massKg - used.massKg),
            volumeM3: max(0, quote.storage.volumeM3 - used.volumeM3)
        )
    }

    private func completeService(runID: Int, state: inout GameState) {
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
        }

        switch stop.task {
        case .travel:
            break
        case .pickupShipment, .pickupContract:
            // Everything claimed at the dock goes on board together.
            for claimed in run.claimedShipmentIDs {
                guard let shipmentIndex = state.shipments.firstIndex(where: { $0.id == claimed })
                else { continue }
                state.shipments[shipmentIndex].location = .vehicle(vehicle.id)
                state.shipments[shipmentIndex].assignedRouteID = route.id
                let offer = state.shipments[shipmentIndex].offer
                state.appendLog(.jobPickedUp(jobID: claimed, origin: offer.origin, destination: offer.destination))
            }
        case .deliverShipment(let jobID):
            settleRouteDelivery(jobID: jobID, routeID: route.id, state: &state)
        case .deliverContract(let contractID):
            let deliverable = state.shipments
                .filter {
                    $0.loadedVehicleID == vehicle.id
                        && $0.offer.contractID == contractID
                        && $0.offer.destination == stop.cityID
                }
                .map(\.id)
                .sorted { $0.rawValue < $1.rawValue }
            for jobID in deliverable {
                settleRouteDelivery(jobID: jobID, routeID: route.id, state: &state)
            }
        case .deliverAll:
            let deliverable = state.shipments
                .filter { $0.loadedVehicleID == vehicle.id && $0.isDeliverable(at: stop.cityID) }
                .map(\.id)
                .sorted { $0.rawValue < $1.rawValue }
            for jobID in deliverable {
                settleRouteDelivery(jobID: jobID, routeID: route.id, state: &state)
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
    private func storeCarriedCargo(vehicleID: VehicleID, cityID: CityID, state: inout GameState) {
        guard let warehouse = state.warehouse(in: cityID) else { return }
        var free = freeStorage(of: warehouse, state: state)
        let carried = state.shipments
            .filter { $0.loadedVehicleID == vehicleID && !$0.isDeliverable(at: cityID) }
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
    private func collectFromWarehouse(
        vehicleID: VehicleID,
        cityID: CityID,
        lotKey: StorageLotKey,
        routeID: RouteID,
        state: inout GameState
    ) {
        guard let warehouse = state.warehouse(in: cityID),
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

    private func settleRouteDelivery(jobID: JobID, routeID: RouteID, state: inout GameState) {
        guard let index = state.shipments.firstIndex(where: { $0.id == jobID }) else { return }
        let offer = state.shipments[index].offer
        state.cash += offer.payout
        state.stats.totalRevenue += offer.payout
        state.stats.deliveredJobs += 1
        if let contractID = offer.contractID,
           let contractIndex = state.activeContracts.firstIndex(where: { $0.id == contractID }) {
            state.activeContracts[contractIndex].shipmentsCompleted += 1
        }
        state.shipments.remove(at: index)
        state.appendLog(.routeShipmentDelivered(
            routeID: routeID,
            jobID: jobID,
            destination: offer.destination,
            revenue: offer.payout
        ))
    }

    private func advanceToNextStop(runID: Int, state: inout GameState) {
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
        applyLeg(&run, from: vehicle.cityID, to: route.stops[next].cityID, vehicleType: vehicleType, clock: state.clock)
        state.routeRuns[runIndex] = run
    }

    private func combinedLoad(_ lhs: LoadSize, _ rhs: LoadSize) -> LoadSize {
        LoadSize(massKg: lhs.massKg + rhs.massKg, volumeM3: lhs.volumeM3 + rhs.volumeM3)
    }

    /// Cleans up after a contract ends. A route the game created *for* that
    /// contract has no reason to exist without it, so it winds down on its own
    /// and says so. A route the player built themselves is never touched — it
    /// may carry other work and the arrangement is theirs — but its now-dead
    /// contract stops are flagged, because silently skipped stops are how a
    /// player ends up paying for laps that collect nothing.
    private func retireRoutes(ofEndedContract contractID: ContractID, state: inout GameState) {
        for route in state.routes {
            let mentionsContract = route.stops.contains { stop in
                switch stop.task {
                case .pickupContract(let id), .deliverContract(let id): id == contractID
                default: false
                }
            }
            guard mentionsContract || route.contractID == contractID else { continue }

            if route.contractID == contractID {
                // Dedicated route: wind it down with its contract.
                if route.isRunning {
                    try? stopRoute(route.id, state: &state)
                }
                state.appendLog(.contractRouteClosed(routeID: route.id, contractID: contractID))
            } else {
                state.appendLog(.routeNeedsReview(routeID: route.id, contractID: contractID))
            }
        }
    }

    /// Closes contracts that reached their term, and clears cancelled ones once
    /// their committed cargo has left the network. Closing never destroys
    /// freight: parcels already accepted keep running to their destination.
    private func expireFinishedContracts(state: inout GameState) {
        let finished = state.activeContracts.filter { contract in
            if let endsAt = contract.endsAt, endsAt <= state.clock { return true }
            // A cancelled contract lingers until nothing of it is left moving.
            guard contract.cancellationRequestedAt != nil else { return false }
            let hasCommittedCargo = state.shipments.contains { $0.offer.contractID == contract.id }
                || state.offers.contains { $0.contractID == contract.id }
            return !hasCommittedCargo
        }
        guard !finished.isEmpty else { return }
        let finishedIDs = Set(finished.map(\.id))

        for contract in finished {
            // Unclaimed obligations at term end count as missed; already
            // accepted parcels are untouched and still pay on delivery.
            let leftover = state.offers.filter {
                $0.source == .contract && $0.contractID == contract.id
            }
            state.offers.removeAll { $0.source == .contract && $0.contractID == contract.id }
            for offer in leftover {
                chargeMissedShipment(offer: offer, state: &state)
            }
            let tally = state.activeContract(contract.id) ?? contract
            state.appendLog(.contractEnded(
                contractID: contract.id,
                completed: tally.shipmentsCompleted,
                missed: tally.shipmentsMissed
            ))
            retireRoutes(ofEndedContract: contract.id, state: &state)
        }
        state.activeContracts.removeAll { finishedIDs.contains($0.id) }
    }

    // MARK: - Contract brief

    /// The three things a player actually decides on: how much rolling stock a
    /// lane ties up, what it clears per day, and how long they are committed.
    /// Everything else (parcel mass, firm names, round-trip km) is detail that
    /// belongs behind a tap, not on the card.
    struct ContractBrief: Equatable, Sendable {
        /// Reference-class vehicles needed to serve the cadence.
        let vehiclesNeeded: Int
        let revenuePerDay: Money
        let costPerDay: Money
        /// Share of those vehicles' time the lane actually uses, 0...1.
        let utilization: Double
        var profitPerDay: Money { revenuePerDay - costPerDay }

        /// True when the lane pays for the capacity it demands.
        var isViable: Bool { profitPerDay > 0 }
    }

    func brief(for terms: some ContractTerms) -> ContractBrief? {
        guard let vehicleType = catalog.vehicleType(terms.referenceVehicleTypeID),
              terms.shipmentIntervalMinutes > 0,
              terms.parcelMassKg > 0 else { return nil }

        var cycleMinutesTotal = 0
        var tripCostTotal = 0
        var revenueTotal = 0
        for destination in terms.destinations {
            let parcels = ContractOffer.parcelCount(
                volumeKg: terms.cycleVolume(for: destination),
                parcelMassKg: terms.parcelMassKg
            )
            guard parcels > 0 else { continue }
            let cycleMinutes = contractCycleMinutes(
                origin: terms.origin,
                destination: destination.cityID,
                distanceKm: destination.distanceKm,
                vehicleType: vehicleType
            )
            cycleMinutesTotal += cycleMinutes * parcels
            tripCostTotal += taskCost(
                totalKm: destination.distanceKm * 2,
                taskMinutes: cycleMinutes,
                vehicleType: vehicleType
            ) * parcels
            revenueTotal += destination.payoutPerParcel * parcels
        }
        guard cycleMinutesTotal > 0 else { return nil }

        // Driving minutes the cadence demands, against the minutes a vehicle
        // can offer in the same window.
        let vehicleMinutesAvailable = Double(terms.shipmentIntervalMinutes)
        let demand = Double(cycleMinutesTotal)
        let vehiclesNeeded = max(1, Int((demand / vehicleMinutesAvailable).rounded(.up)))
        let utilization = min(1, demand / (vehicleMinutesAvailable * Double(vehiclesNeeded)))

        let days = Double(terms.shipmentIntervalMinutes) / Double(GameState.minutesPerDay)
        let ownershipPerCycle = vehicleType.fixedCostPerDay * days * Double(vehiclesNeeded)
        return ContractBrief(
            vehiclesNeeded: vehiclesNeeded,
            revenuePerDay: Money((Double(revenueTotal) / days).rounded()),
            costPerDay: Money(((Double(tripCostTotal) + ownershipPerCycle) / days).rounded()),
            utilization: utilization
        )
    }

    // MARK: - Contract coverage

    /// Whether a contract's freight is actually being moved. This deliberately
    /// measures *flow*, not structure: the old check looked for an auto-created
    /// contract route and cried "no vehicle assigned" even while the player's
    /// own route was hauling the cargo. What matters is where the parcels are.
    enum ContractCoverage: Equatable, Sendable {
        /// Signed, but the first cycle has not posted yet.
        case notStarted(firstShipmentIn: Int)
        /// Every posted parcel is on a vehicle or staged in a warehouse.
        case covered
        /// Some parcels are moving, others are sitting unclaimed.
        case partial(movingParcels: Int, waitingParcels: Int)
        /// Parcels are posted and nothing is carrying them.
        case uncovered(waitingParcels: Int)
    }

    func coverage(of contract: ActiveContract, state: GameState) -> ContractCoverage {
        // Unclaimed obligations still sitting in the market.
        let waiting = state.offers.count {
            $0.source == .contract && $0.contractID == contract.id
        }
        // Accepted parcels: on a truck, at an address, or staged in a warehouse.
        let moving = state.shipments.count { $0.offer.contractID == contract.id }

        if waiting == 0 && moving == 0 {
            let minutes = max(0, state.clock.minutes(until: contract.nextShipmentAt))
            return contract.shipmentsIssued == 0 ? .notStarted(firstShipmentIn: minutes) : .covered
        }
        if waiting == 0 { return .covered }
        if moving == 0 { return .uncovered(waitingParcels: waiting) }
        return .partial(movingParcels: moving, waitingParcels: waiting)
    }

    // MARK: - Estimates (read-only, for UI previews)

    struct JobEstimate: Sendable {
        let deadheadKm: Double
        let totalKm: Double
        let totalMinutes: Int
        let revenue: Money
        let estimatedCost: Money
        var estimatedProfit: Money { revenue - estimatedCost }
    }

    /// Projected outcome of assigning `vehicle` to `offer`. Nil if incompatible.
    func estimate(offer: JobOffer, vehicle: Vehicle, state: GameState) -> JobEstimate? {
        guard state.isVehicleIdle(vehicle.id),
              let vehicleType = catalog.vehicleType(vehicle.typeID),
              offer.load.fits(in: vehicleType.capacity),
              let deadhead = catalog.shortestRoute(from: vehicle.cityID, to: offer.origin) else {
            return nil
        }
        let totalKm = deadhead.distanceKm + offer.distanceKm
        var minutes = loadingMinutes(at: offer.origin) + unloadingMinutes(at: offer.destination)
        minutes += travelMinutes(distanceKm: offer.distanceKm, speedKmh: vehicleType.speedKmh)
        if deadhead.distanceKm > 0 {
            minutes += travelMinutes(distanceKm: deadhead.distanceKm, speedKmh: vehicleType.speedKmh)
        }
        let cost = taskCost(totalKm: totalKm, taskMinutes: minutes, vehicleType: vehicleType)
        return JobEstimate(
            deadheadKm: deadhead.distanceKm,
            totalKm: totalKm,
            totalMinutes: minutes,
            revenue: offer.payout,
            estimatedCost: cost
        )
    }

    struct ContractEstimate: Sendable {
        /// One full cycle with the reference vehicle: load, haul, unload, return.
        let cycleMinutes: Int
        let roundTripKm: Double
        let revenuePerShipment: Money
        let costPerCycle: Money
        var profitPerShipment: Money { revenuePerShipment - costPerCycle }
    }

    /// Projected per-shipment economics of a contract lane with a vehicle class.
    /// Nil if the shipment load does not fit the vehicle.
    func estimate(
        origin: CityID,
        destination: CityID,
        distanceKm: Double,
        shipmentMassKg: Int,
        productID: ProductID,
        payoutPerShipment: Money,
        vehicleType: VehicleTypeDefinition
    ) -> ContractEstimate? {
        let density = catalog.product(productID)?.densityM3PerTon ?? 1
        let volumeM3 = (Double(shipmentMassKg) / 1000 * density * 10).rounded() / 10
        let load = LoadSize(massKg: shipmentMassKg, volumeM3: volumeM3)
        guard load.fits(in: vehicleType.capacity) else { return nil }
        let cycleMinutes = contractCycleMinutes(
            origin: origin,
            destination: destination,
            distanceKm: distanceKm,
            vehicleType: vehicleType
        )
        let cost = taskCost(
            totalKm: distanceKm * 2,
            taskMinutes: cycleMinutes,
            vehicleType: vehicleType
        )
        return ContractEstimate(
            cycleMinutes: cycleMinutes,
            roundTripKm: distanceKm * 2,
            revenuePerShipment: payoutPerShipment,
            costPerCycle: cost
        )
    }

    struct RouteEstimate: Sendable {
        /// Full lap distance including the implicit return leg to the first stop.
        let lapDistanceKm: Double
        /// Travel plus service time for one lap (waiting excluded).
        let lapMinutes: Int
        let revenuePerLap: Money
        let costPerLap: Money
        /// Empty distance of the implicit last-stop -> first-stop leg
        /// (0 when the route naturally loops back to its starting city).
        let loopReturnKm: Double
        var netPerLap: Money { revenuePerLap - costPerLap }
    }

    /// Projected one-lap economics of a route for a given vehicle class.
    /// Contract stops count one shipment per lap; job stops use their payout.
    func estimate(route: Route, vehicleType: VehicleTypeDefinition, state: GameState) -> RouteEstimate? {
        guard !route.stops.isEmpty else { return nil }
        var distanceKm = 0.0
        var minutes = 0
        var revenue: Money = 0
        var cost: Money = 0
        var loopReturnKm = 0.0

        for (index, stop) in route.stops.enumerated() {
            switch stop.task {
            case .travel:
                break
            case .pickupShipment, .pickupContract, .loadFromWarehouse:
                let serviceMinutes = handlingMinutes(loading: true, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
            case .dropToWarehouse:
                // Storing earns nothing by itself: the payout waits for the
                // final leg. Showing it here would flatter a half-built network.
                let serviceMinutes = handlingMinutes(loading: false, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
            case .deliverShipment(let jobID):
                let serviceMinutes = handlingMinutes(loading: false, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                if let shipment = state.shipment(jobID) {
                    revenue += shipment.offer.payout
                }
            case .deliverContract(let contractID):
                let serviceMinutes = handlingMinutes(loading: false, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                if let contract = state.activeContract(contractID),
                   let destination = contract.destinations.first(where: { $0.cityID == stop.cityID }) {
                    revenue += destination.payoutPerParcel
                }
            case .deliverAll:
                let serviceMinutes = handlingMinutes(loading: false, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                // Value what is actually committed to this city on this route.
                revenue += state.shipments(of: route.id)
                    .filter { $0.isDeliverable(at: stop.cityID) }
                    .reduce(0) { $0 + $1.offer.payout }
            }

            let next = route.stops[(index + 1) % route.stops.count]
            guard stop.cityID != next.cityID,
                  let leg = catalog.shortestRoute(from: stop.cityID, to: next.cityID) else { continue }
            let legMinutes = travelMinutes(distanceKm: leg.distanceKm, speedKmh: vehicleType.speedKmh)
            distanceKm += leg.distanceKm
            minutes += legMinutes
            cost += taskCost(totalKm: leg.distanceKm, taskMinutes: legMinutes, vehicleType: vehicleType)
            if index == route.stops.count - 1 {
                loopReturnKm = leg.distanceKm
            }
        }
        return RouteEstimate(
            lapDistanceKm: distanceKm,
            lapMinutes: minutes,
            revenuePerLap: revenue,
            costPerLap: cost,
            loopReturnKm: loopReturnKm
        )
    }
}
