//
//  RouteTaskDisplay.swift
//  Goods&Glory
//
//  How a route task looks and what it is called, in one place.
//
//  The same switch over `RouteTask` was written four times — Fleet, the route
//  builder, the map popup and the operations list — and they had already begun
//  to disagree: adding `pickupLane` meant finding all four. A task's icon,
//  colour and verb are presentation facts about the task itself, so they belong
//  to the task.
//

import SwiftUI

extension RouteTask {
    /// Icon for the task in lists and stop chips.
    var displaySymbol: String {
        switch self {
        case .travel: "arrow.right"
        case .pickupShipment, .pickupContract, .pickupLane: "tray.and.arrow.up.fill"
        case .loadFromWarehouse: "shippingbox.and.arrow.backward.fill"
        case .deliverShipment, .deliverContract, .deliverAll: "tray.and.arrow.down.fill"
        case .dropToWarehouse: "shippingbox.fill"
        case .deliverLane(_, let target): target == .warehouse ? "shippingbox.fill" : "tray.and.arrow.down.fill"
        }
    }

    /// Loading is the company's colour, delivery is mint, storing is sky:
    /// the same three-colour grammar everywhere a stop is drawn.
    func displayTint(accent: Color) -> Color {
        switch self {
        case .travel: Theme.textTertiary
        case .pickupShipment, .pickupContract, .pickupLane, .loadFromWarehouse: accent
        case .deliverShipment, .deliverContract, .deliverAll: Theme.mint
        case .dropToWarehouse: Theme.sky
        case .deliverLane(_, let target): target == .warehouse ? Theme.sky : Theme.mint
        }
    }

    /// What a vehicle is doing while servicing this stop.
    var activityLabel: String {
        switch self {
        case .pickupShipment, .pickupContract, .pickupLane:
            String(localized: "Loading")
        case .loadFromWarehouse:
            String(localized: "Loading from warehouse")
        case .deliverShipment, .deliverContract, .deliverAll:
            String(localized: "Unloading")
        case .dropToWarehouse:
            String(localized: "Storing")
        case .deliverLane(_, let target):
            target == .warehouse ? String(localized: "Storing") : String(localized: "Unloading")
        case .travel:
            String(localized: "Servicing")
        }
    }

    /// True for tasks that put cargo on the vehicle.
    var isPickup: Bool {
        switch self {
        case .pickupShipment, .pickupContract, .pickupLane, .loadFromWarehouse: true
        case .travel, .deliverShipment, .deliverContract, .deliverAll, .dropToWarehouse, .deliverLane: false
        }
    }
}
