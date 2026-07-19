//
//  GameNotification.swift
//  Goods&Glory
//
//  Player-facing alerts derived from campaign LogEntry events. The simulation
//  remains the source of truth; this layer only decides which log lines surface
//  as transient UI notifications.
//

import Foundation

/// Priority / visual family for toast chrome.
enum GameNotificationKind: String, Equatable, Sendable {
    /// Company milestones (HQ founded, …).
    case milestone
    /// Cargo movements (pickup, delivery).
    case operations
    /// Fleet changes (vehicle purchased, …).
    case fleet
}

/// Transient, presentation-ready notice keyed by the underlying log entry id.
struct GameNotification: Identifiable, Equatable, Sendable {
    enum Chrome: String, Equatable, Sendable {
        case brand
        case success
        case warning
    }

    let id: Int
    let kind: GameNotificationKind
    let chrome: Chrome
    let title: String
    let detail: String
    let systemImage: String
    let logAt: GameTime

    /// Returns nil for log events that should stay in the company log only.
    static func make(from entry: LogEntry, catalog: GameCatalog) -> GameNotification? {
        func cityName(_ id: CityID) -> String { catalog.city(id)?.name ?? id.rawValue }

        switch entry.event {
        case .companyFounded(let city):
            return GameNotification(
                id: entry.id,
                kind: .milestone,
                chrome: .brand,
                title: String(localized: "Headquarters established"),
                detail: cityName(city),
                systemImage: "building.2.fill",
                logAt: entry.at
            )
        case .vehiclePurchased(let typeID, let city):
            let typeName = catalog.vehicleType(typeID).map {
                String(localized: String.LocalizationValue($0.name))
            } ?? typeID.rawValue
            return GameNotification(
                id: entry.id,
                kind: .fleet,
                chrome: .brand,
                title: String(localized: "Vehicle acquired"),
                detail: "\(typeName) · \(cityName(city))",
                systemImage: "truck.box.fill",
                logAt: entry.at
            )
        case .jobPickedUp(_, let origin, let destination):
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .brand,
                title: String(localized: "Cargo picked up"),
                detail: "\(cityName(origin)) → \(cityName(destination))",
                systemImage: "shippingbox.fill",
                logAt: entry.at
            )
        case .jobDelivered(_, let destination, let revenue, let cost):
            let profit = revenue - cost
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .success,
                title: String(localized: "Delivered"),
                detail: "\(cityName(destination)) · \(Format.money(profit))",
                systemImage: "checkmark.circle.fill",
                logAt: entry.at
            )
        case .jobAccepted:
            // Acceptance is visible in Jobs; toast reserved for physical milestones.
            return nil
        case .contractSigned(_, let origin, let destination):
            return GameNotification(
                id: entry.id,
                kind: .milestone,
                chrome: .brand,
                title: String(localized: "Contract signed"),
                detail: "\(cityName(origin)) → \(cityName(destination))",
                systemImage: "doc.text.fill",
                logAt: entry.at
            )
        case .vehicleAssignedToRoute, .vehicleUnassignedFromRoute, .routeStarted, .routeStopped:
            // Visible immediately in the route/contract cards; no toast needed.
            return nil
        case .routeShipmentDelivered(_, _, let destination, let revenue):
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .success,
                title: String(localized: "Delivered"),
                detail: "\(cityName(destination)) · \(Format.money(revenue))",
                systemImage: "checkmark.circle.fill",
                logAt: entry.at
            )
        case .routeShipmentSkipped:
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .warning,
                title: String(localized: "Route pickup skipped"),
                detail: String(localized: "Cargo missing or vehicle full"),
                systemImage: "exclamationmark.triangle.fill",
                logAt: entry.at
            )
        case .contractShipmentMissed(_, let penalty):
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .warning,
                title: String(localized: "Contract shipment missed"),
                detail: String(localized: "Compensation paid: \(Format.money(penalty))"),
                systemImage: "exclamationmark.triangle.fill",
                logAt: entry.at
            )
        case .contractEnded(_, let completed, let missed):
            return GameNotification(
                id: entry.id,
                kind: .milestone,
                chrome: missed > 0 ? .warning : .success,
                title: String(localized: "Contract ended"),
                detail: String(localized: "\(completed) delivered · \(missed) missed"),
                systemImage: "doc.text.magnifyingglass",
                logAt: entry.at
            )
        }
    }
}
