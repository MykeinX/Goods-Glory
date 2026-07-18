//
//  Units.swift
//  Goods&Glory
//
//  Canonical simulation units. Presentation formatting happens in UI code only.
//
//  - Money:   whole US dollars (Int). No floating point money in the domain.
//  - Mass:    kilograms (Int).
//  - Volume:  cubic meters (Double).
//  - Time:    game minutes since campaign start (Int).
//

import Foundation

typealias Money = Int

/// A geographic point in WGS 84 decimal degrees.
struct GeoCoordinate: Hashable, Codable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// A point in campaign time, measured in whole game minutes since the campaign started.
struct GameTime: Hashable, Codable, Comparable, Sendable {
    var totalMinutes: Int

    init(totalMinutes: Int) {
        self.totalMinutes = totalMinutes
    }

    static let start = GameTime(totalMinutes: 0)

    /// 1-based campaign day.
    var day: Int { totalMinutes / (24 * 60) + 1 }
    var hour: Int { (totalMinutes % (24 * 60)) / 60 }
    var minute: Int { totalMinutes % 60 }

    static func < (lhs: GameTime, rhs: GameTime) -> Bool {
        lhs.totalMinutes < rhs.totalMinutes
    }

    static func + (lhs: GameTime, rhs: Int) -> GameTime {
        GameTime(totalMinutes: lhs.totalMinutes + rhs)
    }

    func minutes(until other: GameTime) -> Int {
        other.totalMinutes - totalMinutes
    }
}

/// Mass + volume pair used for loads and vehicle capacity checks.
/// Both limits apply independently; neither may be exceeded.
struct LoadSize: Hashable, Codable, Sendable {
    var massKg: Int
    var volumeM3: Double

    func fits(in capacity: LoadSize) -> Bool {
        massKg <= capacity.massKg && volumeM3 <= capacity.volumeM3
    }
}
