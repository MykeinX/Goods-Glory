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
    /// When set, tapping the toast pans the live map to this city (zoom unchanged).
    /// Extend `mapFocusCity(for:)` as new event types gain a geographic target.
    let mapFocusCityID: CityID?

    /// Geographic focus for a log event, if the player should be able to jump there.
    /// Pickup → origin; delivery → destination. Add cases here as event types grow.
    static func mapFocusCity(for event: LogEvent) -> CityID? {
        switch event {
        case .jobPickedUp(_, let origin, _):
            return origin
        case .jobDelivered(_, let destination, _, _):
            return destination
        case .routeShipmentDelivered(_, _, let destination, _):
            return destination
        // Facility and warehouse events are inherently about one place.
        case .facilityCompleted(_, _, let city, _):
            return city
        case .facilityConstructionStarted(_, _, let city, _):
            return city
        case .warehouseFull(let city, _):
            return city
        case .companyFounded, .vehiclePurchased, .jobAccepted, .contractSigned,
             .vehicleAssignedToRoute, .vehicleUnassignedFromRoute, .routeStarted,
             .routeStopped, .routeShipmentSkipped, .contractShipmentMissed, .contractEnded,
             .facilityDemolished, .cargoStored, .cargoLoadedFromWarehouse,
             .contractCancellationRequested, .routeNeedsReview:
            return nil
        }
    }

    /// Returns nil for log events that should stay in the company log only.
    static func make(from entry: LogEntry, catalog: GameCatalog) -> GameNotification? {
        func cityName(_ id: CityID) -> String { catalog.city(id)?.name ?? id.rawValue }
        let focus = mapFocusCity(for: entry.event)

        switch entry.event {
        case .companyFounded(let city):
            return GameNotification(
                id: entry.id,
                kind: .milestone,
                chrome: .brand,
                title: String(localized: "Headquarters established"),
                detail: cityName(city),
                systemImage: "building.2.fill",
                logAt: entry.at,
                mapFocusCityID: focus
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
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .jobPickedUp(_, let origin, let destination):
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .brand,
                title: String(localized: "Cargo picked up"),
                detail: "\(cityName(origin)) → \(cityName(destination))",
                systemImage: "shippingbox.fill",
                logAt: entry.at,
                mapFocusCityID: focus
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
                logAt: entry.at,
                mapFocusCityID: focus
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
                logAt: entry.at,
                mapFocusCityID: focus
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
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .routeShipmentSkipped:
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .warning,
                title: String(localized: "Route pickup skipped"),
                detail: String(localized: "Cargo missing or vehicle full"),
                systemImage: "exclamationmark.triangle.fill",
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .contractShipmentMissed(_, let penalty):
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .warning,
                title: String(localized: "Contract shipment missed"),
                detail: String(localized: "Compensation paid: \(Format.money(penalty))"),
                systemImage: "exclamationmark.triangle.fill",
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .contractEnded(_, let completed, let missed):
            return GameNotification(
                id: entry.id,
                kind: .milestone,
                chrome: missed > 0 ? .warning : .success,
                title: String(localized: "Contract ended"),
                detail: String(localized: "\(completed) delivered · \(missed) missed"),
                systemImage: "doc.text.magnifyingglass",
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .facilityCompleted(_, let kind, let city, let level):
            return GameNotification(
                id: entry.id,
                kind: .milestone,
                chrome: .success,
                title: kind == .office
                    ? String(localized: "Branch open")
                    : String(localized: "Warehouse open"),
                detail: "\(cityName(city)) · \(String(localized: "level \(level)"))",
                systemImage: Format.moduleSymbol(kind),
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .warehouseFull(let city, let refusedParcels):
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .warning,
                title: String(localized: "Warehouse full"),
                detail: String(localized: "\(cityName(city)) · \(refusedParcels) parcel(s) stayed loaded"),
                systemImage: "exclamationmark.triangle.fill",
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .routeNeedsReview:
            // The one case the player must not miss: a route quietly running
            // laps below its potential.
            return GameNotification(
                id: entry.id,
                kind: .operations,
                chrome: .warning,
                title: String(localized: "Route needs editing"),
                detail: String(localized: "A contract ended — the lane runs on spot freight now"),
                systemImage: "pencil.and.list.clipboard",
                logAt: entry.at,
                mapFocusCityID: focus
            )
        case .facilityConstructionStarted, .facilityDemolished,
             .cargoStored, .cargoLoadedFromWarehouse, .contractCancellationRequested:
            // Routine bookkeeping — visible on the facility and city screens.
            return nil
        }
    }
}
