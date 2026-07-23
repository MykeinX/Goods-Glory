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
    private static let verticalBoardScale = 1.274

    func point(latitude: Double, longitude: Double) -> CGPoint {
        return CGPoint(
            x: Self.earthRadiusKm * longitude.clamped(to: -180...180) * .pi / 180,
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
