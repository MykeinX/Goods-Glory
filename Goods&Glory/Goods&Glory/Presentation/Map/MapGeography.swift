//
//  MapGeography.swift
//  Goods&Glory
//
//  Lightweight, presentation-only geography. It gives the strategic map
//  recognizable water, river and regional-boundary silhouettes without
//  introducing a live map service into the simulation or renderer.
//

import Foundation

struct MapGeographyDefinition: Decodable, Sendable {
    let version: Int
    let source: String
    let landMasses: [MapPolygonDefinition]
    let waterBodies: [MapPolygonDefinition]
    let rivers: [MapPolylineDefinition]
    let boundaries: [MapPolylineDefinition]

    static let empty = MapGeographyDefinition(
        version: 0,
        source: "fallback",
        landMasses: [],
        waterBodies: [],
        rivers: [],
        boundaries: []
    )

    var allCoordinates: [GeoCoordinate] {
        landMasses.flatMap(\.points)
            + waterBodies.flatMap(\.points)
            + rivers.flatMap(\.points)
            + boundaries.flatMap(\.points)
    }

    init(
        version: Int,
        source: String,
        landMasses: [MapPolygonDefinition],
        waterBodies: [MapPolygonDefinition],
        rivers: [MapPolylineDefinition],
        boundaries: [MapPolylineDefinition]
    ) {
        self.version = version
        self.source = source
        self.landMasses = landMasses
        self.waterBodies = waterBodies
        self.rivers = rivers
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
        rivers = try container.decode([MapPolylineDefinition].self, forKey: .rivers)
        boundaries = try container.decode([MapPolylineDefinition].self, forKey: .boundaries)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case source
        case landMasses
        case waterBodies
        case rivers
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
}

struct MapPolygonDefinition: Decodable, Sendable {
    let id: String
    let points: [GeoCoordinate]
}

struct MapPolylineDefinition: Decodable, Sendable {
    let id: String
    let points: [GeoCoordinate]
}
