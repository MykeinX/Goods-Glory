//
//  SimulationEngine+Analysis.swift
//  Goods&Glory
//
//  Read-only analysis for the UI: lane bottlenecks and route previews.
//  Nothing here mutates state.
//

import Foundation

extension SimulationEngine {
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

        // Everything this route can lift from the docks it works.
        let lanes = Set(route.coveredLaneIDs)
        let waiting = lanes.reduce(0) { $0 + (state.laneAccrualKg[$1] ?? 0) }
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

    // MARK: - Estimates (read-only, for UI previews)

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
            case .loadFromWarehouse:
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
