//
//  MapBoardSilhouette.swift
//  Goods&Glory
//
//  The globally coarsened world silhouette used by the rounded game board.
//  Gameplay traversal remains in the domain transport graph.
//

import Foundation

struct MapBoardSilhouette: Decodable, Sendable {
    let version: Int
    let source: String
    let landMasses: [MapPolygonDefinition]

    static let empty = MapBoardSilhouette(
        version: 0,
        source: "fallback",
        landMasses: []
    )

    init(version: Int, source: String, landMasses: [MapPolygonDefinition]) {
        self.version = version
        self.source = source
        self.landMasses = landMasses
    }

    static func load(from bundle: Bundle) throws -> MapBoardSilhouette {
        guard let url = bundle.url(
            forResource: "map_board_silhouette",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            MapBoardSilhouette.self,
            from: Data(contentsOf: url)
        )
    }

    @MainActor
    static let bundled: MapBoardSilhouette = {
        do {
            return try load(from: .main)
        } catch {
            assertionFailure("Map board silhouette failed to load: \(error)")
            return .empty
        }
    }()
}

struct MapPolygonDefinition: Decodable, Sendable {
    let id: String
    let points: [GeoCoordinate]
}
