//
//  MapRoadGeometry.swift
//  Goods&Glory
//
//  Baked octilinear polyline per road, authored by generate_trade_network.py
//  against the board's land mask. Presentation data only: routing and travel
//  time stay on RoadDefinition.distanceKm.
//

import Foundation

struct MapRoadGeometry: Decodable, Sendable {
    let version: Int
    let source: String
    let roads: [MapRoadPolyline]

    static let empty = MapRoadGeometry(version: 0, source: "fallback", roads: [])

    init(version: Int, source: String, roads: [MapRoadPolyline]) {
        self.version = version
        self.source = source
        self.roads = roads
    }

    static func load(from bundle: Bundle) throws -> MapRoadGeometry {
        guard let url = bundle.url(
            forResource: "road_geometry",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            MapRoadGeometry.self,
            from: Data(contentsOf: url)
        )
    }

    @MainActor
    static let bundled: MapRoadGeometry = {
        do {
            return try load(from: .main)
        } catch {
            assertionFailure("Map road geometry failed to load: \(error)")
            return .empty
        }
    }()
}

struct MapRoadPolyline: Decodable, Sendable {
    let id: RoadID
    let points: [GeoCoordinate]
}
