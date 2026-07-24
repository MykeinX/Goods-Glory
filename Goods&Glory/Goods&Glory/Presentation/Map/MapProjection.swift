//
//  MapProjection.swift
//  Goods&Glory
//
//  Stable coordinates for the authored strategic game board. Longitude and
//  latitude stay linear; the vertical art scale matches the board silhouette.
//

import CoreGraphics
import Foundation

struct MapProjection: Sendable {
    private static let earthRadiusKm = 6_378.137
    // Matches the authored land bbox (1.955:1) after its 360° × 135°
    // board-coordinate import, so the reference art is not vertically squashed.
    private static let verticalBoardScale = 1.364

    func point(latitude: Double, longitude: Double) -> CGPoint {
        // Board silhouette may author longitudes past ±180 (Pacific wrap /
        // eastern tip). Clamping those to 180 collapses the east edge.
        // Cities stay in the normal range, so they are unaffected.
        return CGPoint(
            x: Self.earthRadiusKm * longitude * .pi / 180,
            y: Self.earthRadiusKm
                * latitude.clamped(to: -90...90)
                * .pi / 180
                * Self.verticalBoardScale
        )
    }

    func point(for coordinate: GeoCoordinate) -> CGPoint {
        point(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func point(for city: CityDefinition) -> CGPoint {
        point(latitude: city.latitude, longitude: city.longitude)
    }
}
