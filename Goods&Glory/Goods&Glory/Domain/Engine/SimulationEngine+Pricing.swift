//
//  SimulationEngine+Pricing.swift
//  Goods&Glory
//
//  The clock and the money: advancing time, job phases, travel and
//  handling durations, cost of a haul and the price it earns.
//

import Foundation

extension SimulationEngine {
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
            if state.nextLaneTickAt < nextEventAt {
                nextEventAt = state.nextLaneTickAt
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
                for module in facility.modules {
                    if module.operationalAt < nextEventAt, !module.hasAnnouncedCompletion {
                        nextEventAt = module.operationalAt
                    }
                    if let endsAt = module.upgradeEndsAt, endsAt < nextEventAt {
                        nextEventAt = endsAt
                    }
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

            while state.nextLaneTickAt <= state.clock {
                accrueLanes(state: &state)
            }
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
        rollRouteDayStats(state: &state)
    }

    func advancePhase(of jobID: JobID, state: inout GameState) {
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
            job.phaseEndsAt = phaseEnd + variedDurationMinutes(
                base: loadingMinutes(at: job.offer.origin),
                worldSeed: state.config.seed,
                kind: "job_load",
                vehicleID: job.vehicleID,
                eventID: job.id.rawValue,
                at: phaseEnd
            )
            state.activeJobs[jobIndex] = job

        case .loading:
            job.phase = .enRoute
            job.phaseStartedAt = phaseEnd
            job.phaseEndsAt = phaseEnd + variedDurationMinutes(
                base: travelMinutes(distanceKm: job.offer.distanceKm, speedKmh: vehicleType.speedKmh),
                worldSeed: state.config.seed,
                kind: "job_leg",
                vehicleID: job.vehicleID,
                eventID: job.id.rawValue,
                at: phaseEnd
            )
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
            job.phaseEndsAt = phaseEnd + variedDurationMinutes(
                base: unloadingMinutes(at: job.offer.destination),
                worldSeed: state.config.seed,
                kind: "job_unload",
                vehicleID: job.vehicleID,
                eventID: job.id.rawValue,
                at: phaseEnd
            )
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

    /// How far real travel / dock time may drift from the nominal (±15%).
    static let durationVarianceFraction = 0.15

    /// Seeded factor in `[1−ε, 1+ε]` so the same vehicle / event / minute always
    /// gets the same delay — never wall-clock randomness.
    func durationVarianceFactor(
        worldSeed: UInt64,
        kind: String,
        vehicleID: VehicleID,
        eventID: Int,
        at clock: GameTime
    ) -> Double {
        var rng = SeededRNG(seed: SeedDerivation.seed(
            worldSeed,
            "duration_var",
            .string(kind),
            .int(vehicleID.rawValue),
            .int(eventID),
            .int(clock.totalMinutes)
        ))
        let span = Self.durationVarianceFraction
        return Double.random(in: (1 - span)...(1 + span), using: &rng)
    }

    /// Applies seeded ±15% variance to a nominal duration. Estimates and
    /// planning previews keep calling the bare `travelMinutes` /
    /// `handlingMinutes`; only live execution goes through here.
    func variedDurationMinutes(
        base: Int,
        worldSeed: UInt64,
        kind: String,
        vehicleID: VehicleID,
        eventID: Int,
        at clock: GameTime
    ) -> Int {
        guard base > 0 else { return base }
        let factor = durationVarianceFactor(
            worldSeed: worldSeed,
            kind: kind,
            vehicleID: vehicleID,
            eventID: eventID,
            at: clock
        )
        return max(1, Int((Double(base) * factor).rounded()))
    }

    /// Loading time scaled by the origin city's urban congestion.
    func loadingMinutes(at city: CityID) -> Int {
        trafficScaled(catalog.economy.loadingMinutes, city: city)
    }

    /// Unloading time scaled by the destination city's urban congestion.
    func unloadingMinutes(at city: CityID) -> Int {
        trafficScaled(catalog.economy.unloadingMinutes, city: city)
    }

    func trafficScaled(_ baseMinutes: Int, city: CityID) -> Int {
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
        state: GameState
    ) -> Money {
        let loaded = haulCost(
            origin: origin,
            destination: destination,
            distanceKm: distanceKm,
            vehicleType: vehicleType
        ).cost

        // The empty leg is priced in, and this is the correction that makes the
        // whole economy work. A shipper pays for a truck to come to them, not
        // for one loaded leg: pricing only the outbound made every shuttle
        // structurally loss-making, because the vehicle still had to drive back.
        // Only part of the return is charged — the market assumes a carrier
        // finds *some* backhaul — so a player who actually finds one keeps the
        // whole second load as profit. That gap is the reward for building a
        // balanced network rather than a one-way pipe.
        let returnMinutes = travelMinutes(distanceKm: distanceKm, speedKmh: vehicleType.speedKmh)
        let emptyReturn = taskCost(
            totalKm: distanceKm,
            taskMinutes: returnMinutes,
            vehicleType: vehicleType
        )
        let returnShare = Double(catalog.economy.emptyReturnSharePercent) / 100
        let laneCost = Double(loaded) + Double(emptyReturn) * returnShare

        // Billing follows how much of the vehicle the freight actually uses,
        // with a floor so a token parcel cannot buy a whole truck cheaply.
        // Half a load earns about half the lane — which is what turns "fill the
        // truck" from advice into arithmetic.
        let utilisation = util(load: load, capacity: vehicleType.capacity)
        let billableShare = max(catalog.economy.fillFloor, utilisation)

        // Home-field advantage, finally applied: it was computed and thrown
        // away before, which is why HQ lanes never felt any different.
        let localPresence = lanePremiumFactor(origin: origin, destination: destination, state: state)

        // Competition squeezes the margin at the same single point contracts
        // use — no second competition parameter anywhere.
        let competition: Double = {
            guard let city = catalog.city(origin) else { return 1 }
            return 1 - 0.30 * CityInsight.make(city: city, catalog: catalog).competitionPercent
        }()

        let margin = Double(catalog.economy.spotMarginPercent) / 100
            * lanePriceFactor(origin: origin, destination: destination)
            * localPresence
            * competition

        return Money(max(1, (laneCost * billableShare * (1 + margin)).rounded()))
    }

    func util(load: LoadSize, capacity: LoadSize) -> Double {
        let massUtil = capacity.massKg > 0 ? Double(load.massKg) / Double(capacity.massKg) : 0
        let volumeUtil = capacity.volumeM3 > 0 ? load.volumeM3 / capacity.volumeM3 : 0
        return min(1, max(massUtil, volumeUtil))
    }

}
