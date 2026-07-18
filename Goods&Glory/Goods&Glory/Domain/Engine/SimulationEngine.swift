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
    private static let nearbyDestinationCount = 5

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

        guard vehicle.isAvailable else { throw CommandError.vehicleBusy }
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
            : catalog.economy.loadingMinutes

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
            state.clock = max(state.clock, nextEventAt)

            // Expired offers are removed before batch generation so the open-offer
            // count at a batch event is independent of how time was chunked.
            removeExpiredOffers(state: &state)

            // Same-timestamp ordering: offer generation first, then job phases by job ID.
            if state.nextOfferBatchAt <= state.clock {
                generateOfferBatch(state: &state)
            }
            let dueJobIDs = state.activeJobs
                .filter { $0.phaseEndsAt <= state.clock }
                .map(\.id)
                .sorted { $0.rawValue < $1.rawValue }
            for jobID in dueJobIDs {
                advancePhase(of: jobID, state: &state)
            }

            if nextEventAt.totalMinutes == target.totalMinutes { break }
        }

        state.clock = max(state.clock, target)
        removeExpiredOffers(state: &state)
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
            job.phaseEndsAt = phaseEnd + catalog.economy.loadingMinutes
            state.activeJobs[jobIndex] = job

        case .loading:
            job.phase = .enRoute
            job.phaseStartedAt = phaseEnd
            job.phaseEndsAt = phaseEnd + travelMinutes(distanceKm: job.offer.distanceKm, speedKmh: vehicleType.speedKmh)
            state.activeJobs[jobIndex] = job

        case .enRoute:
            state.vehicles[vehicleIndex].cityID = job.offer.destination
            state.vehicles[vehicleIndex].odometerKm += job.offer.distanceKm
            job.phase = .unloading
            job.phaseStartedAt = phaseEnd
            job.phaseEndsAt = phaseEnd + catalog.economy.unloadingMinutes
            state.activeJobs[jobIndex] = job

        case .unloading:
            // Settlement: revenue and full task cost applied atomically at delivery.
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
            state.vehicles[vehicleIndex].assignedJobID = nil
            state.activeJobs.remove(at: jobIndex)
            state.appendLog(.jobDelivered(
                jobID: job.id,
                destination: job.offer.destination,
                revenue: job.offer.payout,
                cost: cost
            ))
        }
    }

    func travelMinutes(distanceKm: Double, speedKmh: Double) -> Int {
        max(1, Int((distanceKm / speedKmh * 60).rounded()))
    }

    func taskCost(totalKm: Double, taskMinutes: Int, vehicleType: VehicleTypeDefinition) -> Money {
        let distanceCost = totalKm * vehicleType.costPerKm
        let driverCost = Double(taskMinutes) / 60 * vehicleType.driverCostPerHour
        return Money((distanceCost + driverCost).rounded())
    }

    // MARK: - Offer generation

    private func removeExpiredOffers(state: inout GameState) {
        state.offers.removeAll { $0.expiresAt <= state.clock }
    }

    private func generateOfferBatch(state: inout GameState) {
        let batchIndex = state.nextOfferBatchAt.totalMinutes / catalog.economy.offerGenerationIntervalMinutes
        let generatedAt = state.nextOfferBatchAt
        state.nextOfferBatchAt = generatedAt + catalog.economy.offerGenerationIntervalMinutes

        var vehicleTypesByOrigin: [CityID: [VehicleTypeDefinition]] = [:]
        for vehicle in state.vehicles where vehicle.isAvailable {
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
            let openCount = state.offers.count { $0.origin == origin }
            let availableSlots = catalog.economy.maxOpenOffersPerCity - openCount
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
                guard let referenceType = referenceTypes.randomElement(using: &rng) else { continue }

                let massStepKg = ProductDefinition.shipmentMassStepKg
                let eligibleProducts = catalog.products.compactMap { product -> (
                    product: ProductDefinition, minimumUnits: Int, maximumUnits: Int
                )? in
                    let minimumUnits = product.minimumShipmentMassKg / massStepKg
                        + (product.minimumShipmentMassKg % massStepKg == 0 ? 0 : 1)
                    let volumeLimitedMassKg = Int(
                        (referenceType.capacity.volumeM3 / product.densityM3PerTon * 1000).rounded(.down)
                    )
                    let maximumMassKg = min(
                        product.maximumShipmentMassKg,
                        referenceType.capacity.massKg,
                        volumeLimitedMassKg
                    )
                    let maximumUnits = maximumMassKg / massStepKg
                    guard minimumUnits <= maximumUnits else { return nil }
                    return (product, minimumUnits, maximumUnits)
                }
                guard let selection = eligibleProducts.randomElement(using: &rng),
                      let destination = catalog.nearestCities(
                        from: origin,
                        limit: Self.nearbyDestinationCount
                      ).randomElement(using: &rng),
                      let route = catalog.shortestRoute(from: origin, to: destination) else {
                    continue
                }

                let massKg = Int.random(
                    in: selection.minimumUnits...selection.maximumUnits,
                    using: &rng
                ) * massStepKg
                let volumeM3 = (
                    Double(massKg) / 1000 * selection.product.densityM3PerTon * 10
                ).rounded() / 10
                let directMinutes = catalog.economy.loadingMinutes
                    + travelMinutes(distanceKm: route.distanceKm, speedKmh: referenceType.speedKmh)
                    + catalog.economy.unloadingMinutes
                let directCost = taskCost(
                    totalKm: route.distanceKm,
                    taskMinutes: directMinutes,
                    vehicleType: referenceType
                )
                let percentageProfit = Money((
                    Double(directCost) * Double(catalog.economy.offerProfitMarginPercent) / 100
                ).rounded())
                let payout = directCost + max(catalog.economy.offerMinimumProfit, percentageProfit)

                state.offers.append(JobOffer(
                    id: JobID(rawValue: state.issueID()),
                    origin: origin,
                    destination: destination,
                    productID: selection.product.id,
                    load: LoadSize(massKg: massKg, volumeM3: volumeM3),
                    payout: payout,
                    distanceKm: route.distanceKm,
                    createdAt: generatedAt,
                    expiresAt: generatedAt + catalog.economy.offerLifetimeMinutes
                ))
            }
        }
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
        guard vehicle.isAvailable,
              let vehicleType = catalog.vehicleType(vehicle.typeID),
              offer.load.fits(in: vehicleType.capacity),
              let deadhead = catalog.shortestRoute(from: vehicle.cityID, to: offer.origin) else {
            return nil
        }
        let totalKm = deadhead.distanceKm + offer.distanceKm
        var minutes = catalog.economy.loadingMinutes + catalog.economy.unloadingMinutes
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
}
