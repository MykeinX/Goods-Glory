//
//  SimulationEngine+Analysis.swift
//  Goods&Glory
//
//  Read-only analysis for the UI: contract brief, lane bottleneck,
//  coverage and the estimate previews. Nothing here mutates state.
//

import Foundation

extension SimulationEngine {
    // MARK: - Contract brief

    /// What signing actually changes.
    ///
    /// The old brief priced a contract as a business of its own: a dedicated
    /// truck, its whole round trip and its whole daily ownership cost charged
    /// against one parcel. That was the pre-lane model, and under the current
    /// one it is simply wrong — a contract does not create freight, it locks a
    /// share of a lane the lane already carries. Charging it a dedicated truck
    /// made almost every offer read as a loss, because a 15% share of a lane
    /// never fills a truck it is not entitled to in the first place.
    ///
    /// So the decision is not "is this lane profitable" but two other things:
    /// how much tonnage it reserves, and what the premium over the spot rate
    /// is worth. Capacity is reported, not costed.
    struct ContractBrief: Equatable, Sendable {
        /// Tonnage the commitment reserves every day, across all destinations.
        let committedKgPerDay: Int
        /// What that same freight earns per day carried unsigned, at spot.
        let spotRevenuePerDay: Money
        /// What it earns per day under the commitment.
        let contractRevenuePerDay: Money
        /// Share of one reference-class vehicle's day the cadence consumes.
        /// Above 1 the lane needs more than one truck to itself.
        let fleetLoad: Double
        /// Whole reference-class vehicles the cadence demands.
        let vehiclesNeeded: Int
        /// What one missed parcel costs.
        let penaltyPerParcel: Money

        /// The reason to sign, in one number.
        var premiumPerDay: Money { contractRevenuePerDay - spotRevenuePerDay }
    }

    /// Tonnage per day the company has already promised, across every signed
    /// contract. The number a player needs before signing the next one: each
    /// card says "123% of a truck" on its own, and three such cards quietly add
    /// up to three trucks the fleet does not have.
    func committedKgPerDay(state: GameState) -> Int {
        state.activeContracts.reduce(0) { total, contract in
            total + contract.destinations.reduce(0) { running, destination in
                guard let lane = catalog.lane(destination.laneID) else { return running }
                return running + lane.baseRatePerDayKg * destination.committedShareBps
                    / ContractDestination.fullShareBps
            }
        }
    }

    /// Tonnage per day the fleet can actually move on a lane of this length,
    /// counting the return leg. Deliberately optimistic — full trucks, no
    /// waiting — so that exceeding it is unambiguous trouble rather than a
    /// matter of opinion.
    func fleetKgPerDay(state: GameState, laneDistanceKm: Double) -> Int {
        state.vehicles.reduce(0) { total, vehicle in
            guard let type = catalog.vehicleType(vehicle.typeID), laneDistanceKm > 0 else {
                return total
            }
            let lapMinutes = 2 * travelMinutes(distanceKm: laneDistanceKm, speedKmh: type.speedKmh)
                + catalog.economy.loadingMinutes + catalog.economy.unloadingMinutes
            guard lapMinutes > 0 else { return total }
            let lapsPerDay = Double(GameState.minutesPerDay) / Double(lapMinutes)
            return total + Int(Double(type.capacity.massKg) * lapsPerDay)
        }
    }

    func brief(for terms: some ContractTerms) -> ContractBrief? {
        guard let vehicleType = catalog.vehicleType(terms.referenceVehicleTypeID),
              terms.shipmentIntervalMinutes > 0,
              terms.parcelMassKg > 0 else { return nil }

        let days = Double(terms.shipmentIntervalMinutes) / Double(GameState.minutesPerDay)
        guard days > 0 else { return nil }

        var cycleMinutesTotal = 0
        var contractRevenue = 0
        var spotRevenue = 0
        var committedKgPerDay = 0
        var worstPenalty: Money = 0

        for destination in terms.destinations {
            let parcels = ContractOffer.parcelCount(
                volumeKg: terms.cycleVolume(for: destination),
                parcelMassKg: terms.parcelMassKg
            )
            guard parcels > 0 else { continue }
            cycleMinutesTotal += parcels * contractCycleMinutes(
                origin: terms.origin,
                destination: destination.cityID,
                distanceKm: destination.distanceKm,
                vehicleType: vehicleType
            )
            contractRevenue += destination.payoutPerParcel * parcels

            // The payout was built as `spot × (1 + premium)`, so the spot side
            // is recoverable exactly — no second pricing path to drift from.
            let premium = contractPremium(origin: terms.origin, destination: destination.cityID)
            spotRevenue += Money(
                (Double(destination.payoutPerParcel * parcels) / (1 + premium)).rounded()
            )

            if let lane = catalog.lane(destination.laneID) {
                committedKgPerDay += lane.baseRatePerDayKg
                    * destination.committedShareBps / ContractDestination.fullShareBps
            }
            worstPenalty = max(worstPenalty, Money(
                (Double(destination.payoutPerParcel)
                    * Double(catalog.economy.contractPenaltyPercent) / 100).rounded()
            ))
        }
        guard cycleMinutesTotal > 0 else { return nil }

        let fleetLoad = Double(cycleMinutesTotal) / Double(terms.shipmentIntervalMinutes)
        return ContractBrief(
            committedKgPerDay: committedKgPerDay,
            spotRevenuePerDay: Money((Double(spotRevenue) / days).rounded()),
            contractRevenuePerDay: Money((Double(contractRevenue) / days).rounded()),
            fleetLoad: fleetLoad,
            vehiclesNeeded: max(1, Int(fleetLoad.rounded(.up))),
            penaltyPerParcel: worstPenalty
        )
    }

    // MARK: - Lane bottleneck

    /// Why a lane is not earning more than it does.
    ///
    /// Deliberately one answer, not a dashboard of six: the player needs to
    /// know where to spend next, and a list of everything that is slightly
    /// suboptimal is the same as no answer. Read in priority order — freight
    /// waiting while the truck is elsewhere beats a half-empty truck, which
    /// beats a lane that is simply running well.
    enum RouteBottleneck: Equatable, Sendable {
        /// No vehicle on the lane at all.
        case noVehicle
        /// Freight is piling up at a dock this route serves: add capacity.
        case moreFreightThanCapacity(waitingKg: Int)
        /// Vehicles run, but a large share of the lap carries nothing. An
        /// opportunity, not a fault: a backhaul is one strategy among several,
        /// and a route that never leaves its city cannot have one at all.
        case emptyReturn(emptySharePercent: Int)
        /// Trucks leave the dock partly loaded: cover another lane here.
        case underloaded(loadedSharePercent: Int)
        /// Nothing structural to fix right now.
        case healthy
    }

    func bottleneck(of route: Route, state: GameState) -> RouteBottleneck {
        guard !route.vehicleIDs.isEmpty else { return .noVehicle }

        // Everything this route is on the hook for: freight piling up at the
        // docks it works, plus committed parcels already posted and not yet
        // lifted. Leaving the committed side out was why a route could miss
        // contract loads and still be reported as healthy.
        let lanes = Set(route.coveredLaneIDs)
        let contracts = Set(route.coveredContractIDs)
        let committedWaitingKg = state.offers
            .filter { offer in
                guard offer.source == .contract else { return false }
                if let laneID = offer.laneID, lanes.contains(laneID) { return true }
                return offer.contractID.map { contracts.contains($0) } ?? false
            }
            .reduce(0) { $0 + $1.load.massKg }
        let waiting = lanes.reduce(committedWaitingKg) { $0 + (state.laneAccrualKg[$1] ?? 0) }
        let fleetCapacityKg = route.vehicleIDs.reduce(0) { total, vehicleID in
            total + (state.vehicle(vehicleID)
                .flatMap { catalog.vehicleType($0.typeID) }?.capacity.massKg ?? 0)
        }
        let surplus = waiting - fleetCapacityKg

        // Two different measures, and mixing them up put contradictory numbers
        // on the same card ("55% loaded" beside "trucks leave 74% full"):
        //  - fill: how full the truck was through its working time. Same number
        //    the route card shows, so the hint can never disagree with it.
        //  - empty distance: the share of driven kilometres that carried
        //    nothing. That, and only that, is what a backhaul fixes.
        let fill = route.stats.recentLoadFactor ?? route.stats.loadedShare
        let emptyShare = route.stats.totalKm > 0
            ? route.stats.emptyKm / route.stats.totalKm
            : 0

        // Without lap history we only warn when the dock clearly exceeds one
        // full load — and we report the surplus, not the whole pile.
        guard let loadedShare = fill else {
            if fleetCapacityKg > 0, surplus > 0 {
                return .moreFreightThanCapacity(waitingKg: surplus)
            }
            return .healthy
        }

        // A dock the lane cannot clear in a whole lap outranks everything. This
        // used to sit last, so a lane with a hundred tonnes piling up reported
        // "trucks run 53% full" — true, and useless: the trucks were full
        // outbound and light coming back, and no amount of loading discipline
        // was going to move a backlog that size. More trucks was the answer.
        if fleetCapacityKg > 0, surplus > fleetCapacityKg {
            return .moreFreightThanCapacity(waitingKg: surplus)
        }

        // A backhaul is only suggestable if there is a haul: a route whose stops
        // all sit in one city drives nothing, so the advice would be nonsense.
        let drivesBetweenCities = Set(route.stops.map(\.cityID)).count > 1
        if emptyShare >= 0.35, drivesBetweenCities {
            return .emptyReturn(emptySharePercent: Int((emptyShare * 100).rounded()))
        }
        // Thin loads before a smaller shortage: "add another truck" is the wrong
        // advice when the trucks you have leave half empty — that just creates
        // more empty runners.
        if loadedShare < 0.85 {
            return .underloaded(loadedSharePercent: Int((loadedShare * 100).rounded()))
        }
        if fleetCapacityKg > 0, surplus > 0 {
            return .moreFreightThanCapacity(waitingKg: surplus)
        }
        return .healthy
    }

    // MARK: - Contract coverage

    /// Whether a contract's freight is actually being moved. This deliberately
    /// measures *lane*, not structure: the old check looked for an auto-created
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
        /// Internal revenue already booked by warehouse hand-offs on this lap.
        var handoverCredited: Money = 0

        for (index, stop) in route.stops.enumerated() {
            switch stop.task {
            case .travel:
                break
            case .pickupLane(let laneID):
                let waitingKg = catalog.lane(laneID).map {
                    min(state.laneAccrualKg[$0.id] ?? 0, vehicleType.capacity.massKg)
                } ?? 0
                let serviceMinutes = handlingMinutes(
                    loading: true, massKg: waitingKg, at: stop.cityID, state: state
                )
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                // Preview the spot value of what is waiting right now, capped
                // by what this vehicle class could actually lift in one lap.
                if let lane = catalog.lane(laneID),
                   waitingKg > 0,
                   let distanceKm = catalog.roadDistanceKm(
                       from: lane.originCityID, to: lane.destinationCityID
                   ) {
                    revenue += freightPayout(
                        origin: lane.originCityID,
                        destination: lane.destinationCityID,
                        distanceKm: distanceKm,
                        load: parcelLoad(productID: lane.productID, massKg: waitingKg),
                        vehicleType: vehicleType,
                        state: state
                    )
                }
            case .pickupShipment, .pickupContract, .loadFromWarehouse:
                let serviceMinutes = handlingMinutes(loading: true, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
            case .dropToWarehouse:
                // The customer has not paid yet, but the leg is not working for
                // free either: handing cargo to the network settles what this
                // route spent on it plus the market margin, and the finishing
                // leg books the remainder. Mirrors `creditHandover`.
                let serviceMinutes = handlingMinutes(loading: false, at: stop.cityID, state: state)
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                let owed = Money(
                    (Double(cost) * (1 + Double(handoverMarginPercent) / 100)).rounded()
                )
                revenue += max(0, owed - handoverCredited)
                handoverCredited = max(handoverCredited, owed)
            case .deliverShipment(let jobID):
                let mass = state.shipment(jobID)?.offer.load.massKg ?? 0
                let serviceMinutes = handlingMinutes(
                    loading: false, massKg: mass, at: stop.cityID, state: state
                )
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
                let mass = state.shipments(of: route.id)
                    .filter { $0.isDeliverable(at: stop.cityID) }
                    .reduce(0) { $0 + $1.offer.load.massKg }
                let serviceMinutes = handlingMinutes(
                    loading: false, massKg: mass, at: stop.cityID, state: state
                )
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                // Value what is actually committed to this city on this route.
                revenue += state.shipments(of: route.id)
                    .filter { $0.isDeliverable(at: stop.cityID) }
                    .reduce(0) { $0 + $1.offer.payout }
            case .deliverLane(let laneID, let target):
                let mass = state.shipments(of: route.id)
                    .filter {
                        $0.offer.laneID == laneID
                            && (target == .warehouse || $0.isDeliverable(at: stop.cityID))
                    }
                    .reduce(0) { $0 + $1.offer.load.massKg }
                let serviceMinutes = handlingMinutes(
                    loading: false, massKg: mass, at: stop.cityID, state: state
                )
                minutes += serviceMinutes
                cost += taskCost(totalKm: 0, taskMinutes: serviceMinutes, vehicleType: vehicleType)
                // A firm delivery earns the customer's payout; a warehouse drop
                // earns the hand-off settlement, exactly as the engine books it.
                if target == .destination {
                    revenue += state.shipments(of: route.id)
                        .filter { $0.offer.laneID == laneID && $0.isDeliverable(at: stop.cityID) }
                        .reduce(0) { $0 + $1.offer.payout }
                } else {
                    let owed = Money(
                        (Double(cost) * (1 + Double(handoverMarginPercent) / 100)).rounded()
                    )
                    revenue += max(0, owed - handoverCredited)
                    handoverCredited = max(handoverCredited, owed)
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
