//
//  VehicleStatusDisplay.swift
//  Goods&Glory
//
//  One word and one colour for what a truck is doing. Where it physically is
//  belongs to the state itself — see `GameState.physicalCity(of:)`.
//

import SwiftUI

enum VehicleStatusDisplay {
    static func describe(_ vehicle: Vehicle, state: GameState?) -> (label: String, color: Color) {
        guard let state else { return (String(localized: "idle"), Theme.textTertiary) }
        if let run = state.routeRun(for: vehicle.id) {
            return describeRun(run, state: state)
        }
        if let job = state.activeJob(for: vehicle.id) {
            switch job.phase {
            case .deadheading: return (String(localized: "to pickup"), Theme.mint)
            case .loading: return (String(localized: "loading"), Theme.mint)
            case .enRoute: return (String(localized: "en route"), Theme.mint)
            case .unloading: return (String(localized: "unloading"), Theme.mint)
            }
        }
        if state.route(of: vehicle.id) != nil {
            return (String(localized: "standby"), Theme.sky)
        }
        return (String(localized: "idle"), Theme.textTertiary)
    }

    private static func describeRun(
        _ run: RouteRun,
        state: GameState
    ) -> (label: String, color: Color) {
        switch run.phase {
        case .traveling:
            return (String(localized: "on route"), Theme.mint)
        case .waiting:
            return (String(localized: "waiting"), Theme.sky)
        case .servicing:
            guard let route = state.route(run.routeID),
                  route.stops.indices.contains(run.stopIndex) else {
                return (String(localized: "servicing"), Theme.mint)
            }
            switch route.stops[run.stopIndex].task {
            case .pickupShipment, .pickupContract, .pickupLane, .loadFromWarehouse:
                return (String(localized: "loading"), Theme.mint)
            case .deliverShipment, .deliverContract, .deliverAll:
                return (String(localized: "unloading"), Theme.mint)
            case .dropToWarehouse:
                return (String(localized: "storing"), Theme.sky)
            case .deliverLane(_, let target):
                return target == .warehouse
                    ? (String(localized: "storing"), Theme.sky)
                    : (String(localized: "unloading"), Theme.mint)
            case .travel:
                return (String(localized: "servicing"), Theme.mint)
            }
        }
    }
}
