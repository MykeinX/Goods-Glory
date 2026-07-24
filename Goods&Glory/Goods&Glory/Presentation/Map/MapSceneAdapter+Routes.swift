//
//  MapSceneAdapter+Routes.swift
//  Goods&Glory
//
//  Shared active-road network and route-builder preview snapshots.
//

import CoreGraphics
import Foundation

extension MapSceneAdapter {
    /// Builds one deduplicated visual network for every running route.
    ///
    /// A road shared by fifty vehicles appears once in the snapshot and once
    /// in SpriteKit's batched path. Current transient legs are included so a
    /// vehicle assigned away from the route's first stop never floats off-line.
    @MainActor
    static func activeNetworkOverlays(
        state: GameState,
        catalog: GameCatalog,
        projection: MapProjection,
        corridors: MapCorridorCache
    ) -> [MapRouteOverlay] {
        let routesByID = Dictionary(
            state.routes.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var activeRouteIDs = Set(state.routeRuns.map(\.routeID))
        for route in state.routes where route.isRunning && !route.vehicleIDs.isEmpty {
            activeRouteIDs.insert(route.id)
        }

        var roadIDs = Set<RoadID>()
        func includeLeg(_ origin: CityID, _ destination: CityID) {
            guard origin != destination else { return }
            roadIDs.formUnion(
                corridors.roadIDs(
                    from: origin,
                    to: destination,
                    catalog: catalog,
                    projection: projection
                )
            )
        }

        for routeID in activeRouteIDs {
            guard let route = routesByID[routeID] else { continue }
            var cities: [CityID] = []
            for cityID in route.stops.map(\.cityID) where cities.last != cityID {
                cities.append(cityID)
            }
            guard cities.count > 1 else { continue }
            for index in cities.indices {
                includeLeg(cities[index], cities[(index + 1) % cities.count])
            }
        }

        for run in state.routeRuns where run.phase == .traveling {
            guard let route = routesByID[run.routeID],
                  route.stops.indices.contains(run.stopIndex) else { continue }
            includeLeg(run.legOriginCityID, route.stops[run.stopIndex].cityID)
        }

        return roadIDs
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { roadID in
                guard let points = corridors.points(
                    for: roadID,
                    catalog: catalog,
                    projection: projection
                ), points.count >= 2 else { return nil }
                return MapRouteOverlay(
                    id: "active-\(roadID.rawValue)",
                    anchors: points,
                    kind: .active
                )
            }
    }

    /// Consecutive tasks in one city form one visit. Markers group repeated
    /// physical cities (`1·4`). The builder preview follows the authored visit
    /// order only — it does not invent a return leg to the first city. The
    /// engine still prices that implicit lap close in estimates; running
    /// routes draw the closed network via `activeNetworkOverlays`. Each
    /// `RoadID` is stroked once (Mini Metro), never as an out-and-back polyline.
    static func routePreview(
        route: Route,
        catalog: GameCatalog,
        projection: MapProjection,
        corridors: MapCorridorCache
    ) -> (overlays: [MapRouteOverlay], markers: [MapPlannedVisitMarker]) {
        struct Visit {
            let cityID: CityID
            var hasPickup: Bool
            var hasDelivery: Bool
        }

        var visits: [Visit] = []
        for stop in route.stops {
            let flags: (pickup: Bool, delivery: Bool)
            switch stop.task {
            case .pickupLane, .loadFromWarehouse:
                flags = (true, false)
            case .deliverAll, .dropToWarehouse, .deliverLane:
                flags = (false, true)
            case .travel:
                flags = (false, false)
            }

            if let lastIndex = visits.indices.last,
               visits[lastIndex].cityID == stop.cityID {
                visits[lastIndex].hasPickup = visits[lastIndex].hasPickup || flags.pickup
                visits[lastIndex].hasDelivery = visits[lastIndex].hasDelivery || flags.delivery
            } else {
                visits.append(Visit(
                    cityID: stop.cityID,
                    hasPickup: flags.pickup,
                    hasDelivery: flags.delivery
                ))
            }
        }

        var markerOrder: [CityID] = []
        var markerValues: [CityID: (steps: [Int], pickup: Bool, delivery: Bool)] = [:]
        for (index, visit) in visits.enumerated() {
            var value = markerValues[visit.cityID]
                ?? (steps: [], pickup: false, delivery: false)
            if markerValues[visit.cityID] == nil { markerOrder.append(visit.cityID) }
            value.steps.append(index + 1)
            value.pickup = value.pickup || visit.hasPickup
            value.delivery = value.delivery || visit.hasDelivery
            markerValues[visit.cityID] = value
        }

        let markers = markerOrder.compactMap { cityID -> MapPlannedVisitMarker? in
            guard let city = catalog.city(cityID),
                  let value = markerValues[cityID] else { return nil }
            return MapPlannedVisitMarker(
                id: cityID,
                position: projection.point(for: city),
                stepNumbers: value.steps,
                hasPickup: value.pickup,
                hasDelivery: value.delivery
            )
        }

        let cityIDs = visits.map(\.cityID)

        var roadIDs = Set<RoadID>()
        for index in 0..<max(0, cityIDs.count - 1) {
            let origin = cityIDs[index]
            let destination = cityIDs[index + 1]
            guard origin != destination else { continue }
            roadIDs.formUnion(
                corridors.roadIDs(
                    from: origin,
                    to: destination,
                    catalog: catalog,
                    projection: projection
                )
            )
        }

        let overlays = roadIDs
            .sorted { $0.rawValue < $1.rawValue }
            .compactMap { roadID -> MapRouteOverlay? in
                guard let points = corridors.points(
                    for: roadID,
                    catalog: catalog,
                    projection: projection
                ), points.count >= 2 else { return nil }
                return MapRouteOverlay(
                    id: "preview-\(route.id.rawValue)-\(roadID.rawValue)",
                    anchors: points,
                    kind: .planned
                )
            }

        return (overlays, markers)
    }
}
