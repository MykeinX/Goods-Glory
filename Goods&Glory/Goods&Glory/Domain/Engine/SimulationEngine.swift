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

        let signed = ActiveContract(
            id: offer.id,
            origin: offer.origin,
            destination: offer.destination,
            productID: offer.productID,
            referenceVehicleTypeID: offer.referenceVehicleTypeID,
            shipmentMassKg: offer.shipmentMassKg,
            distanceKm: offer.distanceKm,
            payoutPerShipment: offer.payoutPerShipment,
            shipmentIntervalMinutes: offer.shipmentIntervalMinutes,
            signedAt: state.clock,
            endsAt: state.clock + catalog.economy.contractDurationDays * GameState.minutesPerDay,
            nextShipmentAt: state.clock,
            shipmentsIssued: 0,
            shipmentsCompleted: 0,
            shipmentsMissed: 0,
            penaltiesPaid: 0,
            originFirmID: offer.originFirmID,
            destinationFirmID: offer.destinationFirmID
        )
        state.contractOffers.remove(at: index)
        state.activeContracts.append(signed)
        state.appendLog(.contractSigned(
            contractID: signed.id,
            origin: signed.origin,
            destination: signed.destination
        ))
        postContractShipment(contractIndex: state.activeContracts.count - 1, state: &state)
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
            let route = Route(
                id: RouteID(rawValue: state.issueID()),
                name: "\(originName) → \(destinationName)",
                contractID: contractID,
                stops: [
                    RouteStop(id: state.issueID(), cityID: contract.origin, task: .pickupContract(contractID)),
                    RouteStop(id: state.issueID(), cityID: contract.destination, task: .deliverContract(contractID))
                ],
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

    /// The recurring load a contract ships each cycle (volume from product density).
    func contractLoad(_ contract: ActiveContract) -> LoadSize {
        let density = catalog.product(contract.productID)?.densityM3PerTon ?? 1
        let volumeM3 = (Double(contract.shipmentMassKg) / 1000 * density * 10).rounded() / 10
        return LoadSize(massKg: contract.shipmentMassKg, volumeM3: volumeM3)
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
                if contract.nextShipmentAt < nextEventAt, state.clock < contract.endsAt {
                    nextEventAt = contract.nextShipmentAt
                }
                if contract.endsAt < nextEventAt {
                    nextEventAt = contract.endsAt
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

            chargeFixedCostsIfNeeded(state: &state)
            removeExpiredOffers(state: &state)
            removeExpiredContractOffers(state: &state)

            if state.nextOfferBatchAt <= state.clock {
                generateOfferBatch(state: &state)
            }
            if state.nextContractBatchAt <= state.clock {
                generateContractOfferBatch(state: &state)
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

    /// Freight revenue for a loaded haul at the given utilisation, urgency
    /// multiplier and regional lane price factor.
    func freightPayout(
        vehicleType: VehicleTypeDefinition,
        distanceKm: Double,
        util: Double,
        urgencyMultiplier: Double,
        laneFactor: Double = 1.0
    ) -> Money {
        let clampedUtil = min(1, max(0, util))
        let fillFactor = catalog.economy.fillFloor + (1 - catalog.economy.fillFloor) * clampedUtil
        let raw = vehicleType.freightRatePerKm * distanceKm * fillFactor * urgencyMultiplier * laneFactor
        return Money(max(1, raw.rounded()))
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
        guard days > 0, !state.vehicles.isEmpty else {
            state.lastFixedCostDay = max(state.lastFixedCostDay, currentDay)
            return
        }
        var dailyTotal = 0.0
        for vehicle in state.vehicles {
            if let type = catalog.vehicleType(vehicle.typeID) {
                dailyTotal += type.fixedCostPerDay
            }
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
        let utilisation = util(load: load, capacity: referenceType.capacity)
        let payout = freightPayout(
            vehicleType: referenceType,
            distanceKm: route.distanceKm,
            util: utilisation,
            urgencyMultiplier: tier.multiplier,
            laneFactor: lanePriceFactor(origin: origin, destination: destination)
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

    private func generateContractOfferBatch(state: inout GameState) {
        let batchIndex = state.nextContractBatchAt.totalMinutes
            / catalog.economy.contractOfferIntervalMinutes
        let generatedAt = state.nextContractBatchAt
        state.nextContractBatchAt = generatedAt + catalog.economy.contractOfferIntervalMinutes

        let openSlots = catalog.economy.maxOpenContractOffers - state.contractOffers.count
        guard openSlots > 0 else { return }

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

        for slot in 0..<openSlots {
            var rng = SeededRNG(seed: SeedDerivation.seed(
                state.config.seed, "contract_batch", .int(batchIndex), .int(slot)
            ))
            guard let referenceType = referenceTypes.randomElement(using: &rng) else { continue }
            let originCandidates = state.vehicles.map(\.cityID) + [state.config.hqCity]
            let origin = originCandidates.randomElement(using: &rng) ?? state.config.hqCity
            guard let product = pickSuppliedProduct(origin: origin, referenceType: referenceType, rng: &rng),
                  let destination = pickDemandingDestination(
                    origin: origin,
                    productID: product.id,
                    preferShort: Bool.random(using: &rng),
                    rng: &rng
                  ),
                  let route = catalog.shortestRoute(from: origin, to: destination),
                  let load = makeLoad(
                    product: product,
                    capacity: referenceType.capacity,
                    preferHighFill: true,
                    rng: &rng
                  ) else {
                continue
            }

            // Dedicated lanes are priced on the full cycle (loaded leg + empty
            // return) plus a stable margin scaled by the lane's price level.
            let cycleMinutes = contractCycleMinutes(
                origin: origin,
                destination: destination,
                distanceKm: route.distanceKm,
                vehicleType: referenceType
            )
            let cycleCost = taskCost(
                totalKm: route.distanceKm * 2,
                taskMinutes: cycleMinutes,
                vehicleType: referenceType
            )
            let margin = Double(catalog.economy.contractMarginPercent) / 100
                * lanePriceFactor(origin: origin, destination: destination)
            let payout = Money(max(1, (Double(cycleCost) * (1 + margin)).rounded()))
            // Shipments repeat on whole days; the interval always leaves the
            // reference vehicle slack beyond one full cycle.
            let minimumInterval = Int(Double(cycleMinutes) * 1.2)
            let intervalDays = max(1, (minimumInterval + GameState.minutesPerDay - 1) / GameState.minutesPerDay)
                + Int.random(in: 0...1, using: &rng)
            let interval = intervalDays * GameState.minutesPerDay

            state.contractOffers.append(ContractOffer(
                id: ContractID(rawValue: state.issueID()),
                origin: origin,
                destination: destination,
                productID: product.id,
                referenceVehicleTypeID: referenceType.id,
                shipmentMassKg: load.massKg,
                distanceKm: route.distanceKm,
                payoutPerShipment: payout,
                shipmentIntervalMinutes: interval,
                originFirmID: catalog.supplierFirm(city: origin, product: product.id)?.id,
                destinationFirmID: catalog.receiverFirm(city: destination, product: product.id)?.id,
                createdAt: generatedAt,
                expiresAt: generatedAt + catalog.economy.offerLifetimeMinutes * 2
            ))
        }
    }

    private func postDueContractShipments(state: inout GameState) {
        for index in state.activeContracts.indices {
            while state.activeContracts[index].nextShipmentAt <= state.clock,
                  state.clock < state.activeContracts[index].endsAt {
                postContractShipment(contractIndex: index, state: &state)
            }
        }
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

    /// Posts one due shipment obligation. Every shipment must be delivered
    /// before the next one is due (its deadline) or compensation is charged.
    private func postContractShipment(contractIndex: Int, state: inout GameState) {
        guard state.activeContracts.indices.contains(contractIndex) else { return }
        var contract = state.activeContracts[contractIndex]
        guard state.clock < contract.endsAt else { return }

        state.offers.append(JobOffer(
            id: JobID(rawValue: state.issueID()),
            origin: contract.origin,
            destination: contract.destination,
            productID: contract.productID,
            load: contractLoad(contract),
            payout: contract.payoutPerShipment,
            distanceKm: contract.distanceKm,
            urgency: .normal,
            source: .contract,
            contractID: contract.id,
            originFirmID: contract.originFirmID,
            destinationFirmID: contract.destinationFirmID,
            createdAt: state.clock,
            expiresAt: state.clock + contract.shipmentIntervalMinutes
        ))
        contract.shipmentsIssued += 1
        contract.nextShipmentAt = contract.nextShipmentAt + contract.shipmentIntervalMinutes
        state.activeContracts[contractIndex] = contract
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
        case .travel, .pickupContract, .deliverContract:
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
            guard cityID == contract.destination else { throw CommandError.unknownReference }
            task = .deliverContract(contractID)
        }

        // Repeated taps are harmless and must not create multiple recurring
        // claims for the same contract action on one route.
        guard !state.routes[routeIndex].stops.contains(where: { $0.task == task }) else { return }
        let stop = RouteStop(id: state.issueID(), cityID: cityID, task: task)
        state.routes[routeIndex].stops.insert(stop, at: insertionIndex + 1)
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
        let legacyJobIDs = Set(block.compactMap { stop -> JobID? in
            switch stop.task {
            case .pickupShipment(let jobID), .deliverShipment(let jobID): return jobID
            case .travel, .pickupContract, .deliverContract: return nil
            }
        })
        let shipments = try legacyJobIDs.map { jobID -> RouteShipment in
            guard let shipment = state.routeShipments.first(where: {
                $0.id == jobID && $0.routeID == routeID
            }) else {
                throw CommandError.unknownReference
            }
            guard shipment.loadedVehicleID == nil else { throw CommandError.vehicleBusy }
            return shipment
        }.sorted { $0.id.rawValue < $1.id.rawValue }

        state.routeShipments.removeAll {
            $0.routeID == routeID && legacyJobIDs.contains($0.id)
        }
        state.routes[routeIndex].stops.removeAll { stop in
            if blockStopIDs.contains(stop.id) { return true }
            switch stop.task {
            case .pickupShipment(let jobID), .deliverShipment(let jobID):
                return legacyJobIDs.contains(jobID)
            case .travel, .pickupContract, .deliverContract:
                return false
            }
        }
        for shipment in shipments {
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
        state.routeShipments.append(RouteShipment(
            id: offer.id,
            offer: offer,
            routeID: routeID,
            loadedVehicleID: nil
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
        guard let shipmentIndex = state.routeShipments.firstIndex(where: {
            $0.id == jobID && $0.routeID == routeID
        }) else {
            throw CommandError.unknownReference
        }
        guard state.routeShipments[shipmentIndex].loadedVehicleID == nil else {
            throw CommandError.vehicleBusy
        }
        let shipment = state.routeShipments.remove(at: shipmentIndex)
        state.routes[routeIndex].stops.removeAll {
            $0.task == .pickupShipment(jobID) || $0.task == .deliverShipment(jobID)
        }
        detachShipment(shipment, state: &state)
    }

    /// Contract obligations return to the market (or settle as missed);
    /// forfeited spot cargo simply disappears without payment.
    private func detachShipment(_ shipment: RouteShipment, state: inout GameState) {
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
        guard pickupContracts == deliveryContracts else {
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
        let orphans = state.routeShipments
            .filter { $0.routeID == routeID }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        state.routeShipments.removeAll { $0.routeID == routeID }
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
            claimedShipmentID: nil,
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

        func startService(minutes: Int, claiming shipmentID: JobID?) {
            run.phase = .servicing
            run.phaseStartedAt = state.clock
            run.phaseEndsAt = state.clock + minutes
            run.claimedShipmentID = shipmentID
            state.routeRuns[runIndex] = run
        }
        func waitForCargo() {
            run.phase = .waiting
            run.phaseStartedAt = state.clock
            run.phaseEndsAt = Self.waitSentinel
            run.claimedShipmentID = nil
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
                $0.id != runID && $0.claimedShipmentID == jobID
            }
            guard !run.isWindingDown,
                  let shipment = state.routeShipment(jobID),
                  shipment.loadedVehicleID == nil,
                  !claimedByAnotherRun else {
                skip()
                return
            }
            guard shipment.offer.origin == stop.cityID else {
                skip(loggingJob: jobID)
                return
            }
            guard combinedLoad(state.cargoLoad(of: vehicle.id), shipment.offer.load)
                .fits(in: vehicleType.capacity) else {
                skip(loggingJob: jobID)
                return
            }
            startService(minutes: loadingMinutes(at: stop.cityID), claiming: jobID)

        case .pickupContract(let contractID):
            guard !run.isWindingDown, state.activeContract(contractID) != nil else {
                skip()
                return
            }
            let pending = state.offers
                .filter { $0.source == .contract && $0.contractID == contractID && $0.origin == stop.cityID }
                .min { $0.id.rawValue < $1.id.rawValue }
            guard let offer = pending else {
                waitForCargo()
                return
            }
            guard combinedLoad(state.cargoLoad(of: vehicle.id), offer.load)
                .fits(in: vehicleType.capacity) else {
                skip(loggingJob: offer.id)
                return
            }
            // Claim now so the obligation cannot expire mid-loading.
            state.offers.removeAll { $0.id == offer.id }
            state.routeShipments.append(RouteShipment(
                id: offer.id,
                offer: offer,
                routeID: route.id,
                loadedVehicleID: nil
            ))
            startService(minutes: loadingMinutes(at: stop.cityID), claiming: offer.id)

        case .deliverShipment(let jobID):
            guard let shipment = state.routeShipment(jobID),
                  shipment.loadedVehicleID == vehicle.id else {
                skip()
                return
            }
            guard shipment.offer.destination == stop.cityID else {
                skip(loggingJob: jobID)
                return
            }
            startService(minutes: unloadingMinutes(at: stop.cityID), claiming: jobID)

        case .deliverContract(let contractID):
            let carried = state.routeShipments.contains {
                $0.loadedVehicleID == vehicle.id
                    && $0.offer.contractID == contractID
                    && $0.offer.destination == stop.cityID
            }
            guard carried else {
                skip()
                return
            }
            startService(minutes: unloadingMinutes(at: stop.cityID), claiming: nil)
        }
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
            if let claimed = run.claimedShipmentID,
               let shipmentIndex = state.routeShipments.firstIndex(where: { $0.id == claimed }) {
                state.routeShipments[shipmentIndex].loadedVehicleID = vehicle.id
                let offer = state.routeShipments[shipmentIndex].offer
                state.appendLog(.jobPickedUp(jobID: claimed, origin: offer.origin, destination: offer.destination))
            }
        case .deliverShipment(let jobID):
            settleRouteDelivery(jobID: jobID, routeID: route.id, state: &state)
        case .deliverContract(let contractID):
            let deliverable = state.routeShipments
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
        }
        if let runIndex = state.routeRuns.firstIndex(where: { $0.id == runID }) {
            state.routeRuns[runIndex].claimedShipmentID = nil
        }
        advanceToNextStop(runID: runID, state: &state)
    }

    private func settleRouteDelivery(jobID: JobID, routeID: RouteID, state: inout GameState) {
        guard let index = state.routeShipments.firstIndex(where: { $0.id == jobID }) else { return }
        let offer = state.routeShipments[index].offer
        state.cash += offer.payout
        state.stats.totalRevenue += offer.payout
        state.stats.deliveredJobs += 1
        if let contractID = offer.contractID,
           let contractIndex = state.activeContracts.firstIndex(where: { $0.id == contractID }) {
            state.activeContracts[contractIndex].shipmentsCompleted += 1
        }
        state.routeShipments.remove(at: index)
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
           state.routeShipments.allSatisfy({ $0.loadedVehicleID != vehicle.id }) {
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
                run.claimedShipmentID = nil
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

    private func expireFinishedContracts(state: inout GameState) {
        let finished = state.activeContracts.filter { $0.endsAt <= state.clock }
        guard !finished.isEmpty else { return }
        for contract in finished {
            // Obligations still open at term end count as missed.
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
            // The contract's route survives (it may carry other work); its
            // contract stops simply stop producing cargo and are skipped.
        }
        state.activeContracts.removeAll { $0.endsAt <= state.clock }
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
            case .pickupShipment, .pickupContract:
                let serviceMinutes = loadingMinutes(at: stop.cityID)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
            case .deliverShipment(let jobID):
                let serviceMinutes = unloadingMinutes(at: stop.cityID)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                if let shipment = state.routeShipment(jobID) {
                    revenue += shipment.offer.payout
                }
            case .deliverContract(let contractID):
                let serviceMinutes = unloadingMinutes(at: stop.cityID)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                if let contract = state.activeContract(contractID) {
                    revenue += contract.payoutPerShipment
                }
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
