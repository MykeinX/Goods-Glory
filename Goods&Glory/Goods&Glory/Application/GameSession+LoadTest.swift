//
//  GameSession+LoadTest.swift
//  Goods&Glory
//
//  Developer-only: put a large fleet on the map at once.
//
//  The map has to stay smooth with hundreds of vehicles moving, and reaching
//  that fleet by playing takes days. This seeds one directly so the render
//  budget can be read off the performance HUD instead of argued about.
//
//  It writes state the engine would otherwise build up over a campaign, which
//  is why it is not a GameCommand: it deliberately skips the rules — no cash is
//  charged and no lane is claimed. Compiled out of release builds entirely.
//

#if DEBUG

import Foundation

extension GameSession {
    /// Spreads `count` vehicles across the whole road network, mid-journey.
    ///
    /// Vehicles are distributed over every city with a neighbour rather than
    /// stacked on one corridor, and given staggered leg durations so they fan
    /// out along their lines instead of moving as one block. Both matter: a
    /// hundred vehicles sitting on the same point is a much cheaper frame than
    /// a hundred spread across the board, and the cheap case is not the one
    /// worth measuring.
    func seedLoadTestFleet(count: Int) {
        guard var current = state,
              let vehicleType = catalog.vehicleTypes.first,
              let product = catalog.products.first else { return }

        let legs: [(origin: CityID, destination: CityID)] = catalog.cities.flatMap { city in
            catalog.reachableCities(from: city.id)
                .filter { $0 != city.id }
                .map { (origin: city.id, destination: $0) }
        }
        guard !legs.isEmpty else { return }

        var nextVehicle = (current.vehicles.map(\.id.rawValue).max() ?? 0) + 1
        var nextRoute = (current.routes.map(\.id.rawValue).max() ?? 0) + 1
        var nextRun = (current.routeRuns.map(\.id).max() ?? 0) + 1
        var nextJob = (current.shipments.map(\.id.rawValue).max() ?? 0) + 1

        for index in 0..<count {
            let leg = legs[index % legs.count]
            let vehicleID = VehicleID(rawValue: nextVehicle)
            let routeID = RouteID(rawValue: nextRoute)
            nextVehicle += 1
            nextRoute += 1

            current.vehicles.append(
                Vehicle(
                    id: vehicleID,
                    typeID: vehicleType.id,
                    cityID: leg.origin,
                    odometerKm: 0
                )
            )
            current.routes.append(
                Route(
                    id: routeID,
                    name: "LOAD \(index + 1)",
                    stops: [
                        RouteStop(id: 1, cityID: leg.destination, task: .travel),
                        RouteStop(id: 2, cityID: leg.origin, task: .travel),
                    ],
                    vehicleIDs: [vehicleID],
                    isRunning: true
                )
            )
            // Staggered so the fleet is strung out along its corridors rather
            // than departing together.
            let duration = 240 + (index % 47) * 13
            current.routeRuns.append(
                RouteRun(
                    id: nextRun,
                    routeID: routeID,
                    vehicleID: vehicleID,
                    stopIndex: 0,
                    phase: .traveling,
                    phaseStartedAt: current.clock,
                    phaseEndsAt: current.clock + duration,
                    legOriginCityID: leg.origin,
                    legDistanceKm: 400,
                    lapStartedAt: current.clock,
                    claimedShipmentIDs: [],
                    isWindingDown: false
                )
            )
            // Loads are spread across the whole range, not just full or empty,
            // so the capsule fill can be judged at every level it will really
            // show. A quarter of the fleet runs empty, as it would in play.
            let share = Double((index % 8)) / 7.0
            if share > 0.01 {
                let jobID = JobID(rawValue: nextJob)
                nextJob += 1
                current.shipments.append(
                    Shipment(
                        id: jobID,
                        offer: JobOffer(
                            id: jobID,
                            origin: leg.origin,
                            destination: leg.destination,
                            productID: product.id,
                            load: LoadSize(
                                massKg: Int(Double(vehicleType.capacity.massKg) * share),
                                volumeM3: vehicleType.capacity.volumeM3 * share * 0.8
                            ),
                            payout: 0,
                            distanceKm: 400,
                            laneID: nil,
                            originFirmID: nil,
                            destinationFirmID: nil,
                            createdAt: current.clock,
                            expiresAt: current.clock + 10_000
                        ),
                        location: .vehicle(vehicleID),
                        assignedRouteID: routeID
                    )
                )
            }
            nextRun += 1
        }

        replaceStateForLoadTest(current)
    }

    /// Removes everything `seedLoadTestFleet` added, by the name it stamps on
    /// its routes, so a campaign can be handed back roughly as it was found.
    func clearLoadTestFleet() {
        guard var current = state else { return }
        let seeded = Set(
            current.routes.filter { $0.name.hasPrefix("LOAD ") }.map(\.id)
        )
        guard !seeded.isEmpty else { return }
        let vehicles = Set(
            current.routes.filter { seeded.contains($0.id) }.flatMap(\.vehicleIDs)
        )
        current.shipments.removeAll {
            $0.assignedRouteID.map { seeded.contains($0) } ?? false
        }
        current.routeRuns.removeAll { seeded.contains($0.routeID) }
        current.routes.removeAll { seeded.contains($0.id) }
        current.vehicles.removeAll { vehicles.contains($0.id) }
        replaceStateForLoadTest(current)
    }
}

#endif
