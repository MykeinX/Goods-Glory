//
//  MapProjection.swift
//  Goods&Glory
//
//  Stable geographic coordinates for the strategic world map. Web Mercator
//  keeps every catalog point in the same world space as regions are added;
//  approximately one scene unit represents one projected kilometre.
//

import CoreGraphics
import Foundation

struct MapProjection: Sendable {
    private static let earthRadiusKm = 6_378.137
    private static let maximumLatitude = 85.05112878

    func point(latitude: Double, longitude: Double) -> CGPoint {
        let latitude = latitude.clamped(to: -Self.maximumLatitude...Self.maximumLatitude)
        let latitudeRadians = latitude * .pi / 180
        let longitudeRadians = longitude * .pi / 180
        return CGPoint(
            x: Self.earthRadiusKm * longitudeRadians,
            y: Self.earthRadiusKm * log(tan(.pi / 4 + latitudeRadians / 2))
        )
    }

    func point(for coordinate: GeoCoordinate) -> CGPoint {
        point(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    func point(for city: CityDefinition) -> CGPoint {
        point(latitude: city.latitude, longitude: city.longitude)
    }
}
