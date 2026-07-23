//
//  MapBoundaryAtlas.swift
//  Goods&Glory
//
//  Presentation-only country borders at their final render detail.
//

import Foundation

struct MapBoundaryAtlas: Decodable, Sendable {
    let version: Int
    let source: String
    let lines: [[GeoCoordinate]]

    static let empty = MapBoundaryAtlas(
        version: 0,
        source: "fallback",
        lines: []
    )

    static func load(from bundle: Bundle) throws -> MapBoundaryAtlas {
        guard let url = bundle.url(
            forResource: "map_boundaries",
            withExtension: "json"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(
            MapBoundaryAtlas.self,
            from: Data(contentsOf: url)
        )
    }

    /// One immutable decode per launch, shared by every map surface.
    @MainActor
    static let bundled: MapBoundaryAtlas = {
        do {
            return try load(from: .main)
        } catch {
            assertionFailure("Map boundary atlas failed to load: \(error)")
            return .empty
        }
    }()
}
