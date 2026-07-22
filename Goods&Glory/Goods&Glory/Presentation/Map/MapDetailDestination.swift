//
//  MapDetailDestination.swift
//  Goods&Glory
//
//  Where a map tap can lead. Shared by the tab that presents the destination
//  and the chrome that requests it.
//

import Foundation

/// Cities no longer travel here — they open as a sheet over the live map.
enum MapDetailDestination: Identifiable {
    case vehicle(VehicleID)

    var id: String {
        switch self {
        case .vehicle(let id): return "vehicle-\(id.rawValue)"
        }
    }
}

