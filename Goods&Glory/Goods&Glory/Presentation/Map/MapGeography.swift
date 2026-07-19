//
//  MapGeography.swift
//  Goods&Glory
//
//  Lightweight, presentation-only geography. It gives the strategic map
//  recognizable land, water and country-boundary silhouettes without
//  introducing a live map service into the simulation or renderer.
//

import Foundation

struct MapGeographyDefinition: Decodable, Sendable {
    let version: Int
    let source: String
    let landMasses: [MapPolygonDefinition]
    let waterBodies: [MapPolygonDefinition]
    let boundaries: [MapPolylineDefinition]

    static let empty = MapGeographyDefinition(
        version: 0,
        source: "fallback",
        landMasses: [],
        waterBodies: [],
        boundaries: []
    )

    var allCoordinates: [GeoCoordinate] {
        landMasses.flatMap(\.points)
            + waterBodies.flatMap(\.points)
            + boundaries.flatMap(\.points)
    }

    init(
        version: Int,
        source: String,
        landMasses: [MapPolygonDefinition],
        waterBodies: [MapPolygonDefinition],
        boundaries: [MapPolylineDefinition]
    ) {
        self.version = version
        self.source = source
        self.landMasses = landMasses
        self.waterBodies = waterBodies
        self.boundaries = boundaries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        source = try container.decode(String.self, forKey: .source)
        landMasses = try container.decodeIfPresent(
            [MapPolygonDefinition].self,
            forKey: .landMasses
        ) ?? []
        waterBodies = try container.decode([MapPolygonDefinition].self, forKey: .waterBodies)
        boundaries = try container.decode([MapPolylineDefinition].self, forKey: .boundaries)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case source
        case landMasses
        case waterBodies
        case boundaries
    }

    static func load(from bundle: Bundle) throws -> MapGeographyDefinition {
        guard let url = bundle.url(forResource: "map_geography", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            MapGeographyDefinition.self,
            from: Data(contentsOf: url)
        )
    }

    /// The bundled geography, decoded once per launch.
    ///
    /// The file is ~1.1 MB of nested `{latitude, longitude}` objects — nearly
    /// 13,000 of them — and decoding it is not cheap. Every `InteractiveMapView`
    /// used to decode its own copy in `makeCoordinator`, and there are four
    /// mount points (founding, map tab, city detail, route builder). Opening
    /// the route builder mid-game therefore re-parsed the whole world on the
    /// main thread while the player waited.
    ///
    /// The value is immutable, so one shared copy is all anyone needs.
    @MainActor
    static let bundled: MapGeographyDefinition = {
        do {
            return try load(from: .main)
        } catch {
            assertionFailure("Map geography failed to load: \(error)")
            return .empty
        }
    }()
}

struct MapPolygonDefinition: Decodable, Sendable {
    let id: String
    let points: [GeoCoordinate]
}

struct MapPolylineDefinition: Decodable, Sendable {
    let id: String
    let points: [GeoCoordinate]
}
