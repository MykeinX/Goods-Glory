//
//  Formatters.swift
//  Goods&Glory
//
//  Presentation-side formatting of canonical domain units. The domain stores
//  whole dollars, kilograms, cubic meters and game minutes; everything the
//  player reads is formatted here.
//

import SwiftUI

enum Format {
    static func money(_ amount: Money) -> String {
        let sign = amount < 0 ? "-" : ""
        return "\(sign)$\(abs(amount).formatted(.number.grouping(.automatic)))"
    }

    static func gameTime(_ time: GameTime) -> String {
        String(
            localized: "Day \(time.day), \(String(format: "%02d:%02d", time.hour, time.minute))",
            comment: "Campaign clock, e.g. Day 3, 14:05"
        )
    }

    static func duration(minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 { return String(localized: "\(mins) min") }
        if mins == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(mins) min")
    }

    static func distance(km: Double) -> String {
        String(localized: "\(Int(km.rounded())) km")
    }

    static func mass(kg: Int) -> String {
        kg >= 1000
            ? String(localized: "\((Double(kg) / 1000).formatted(.number.precision(.fractionLength(0...1)))) t")
            : String(localized: "\(kg) kg")
    }

    static func volume(m3: Double) -> String {
        String(localized: "\(m3.formatted(.number.precision(.fractionLength(0...1)))) m³")
    }

    /// Fleet / map vehicle code, e.g. `VAN-03` from type name + runtime id.
    static func vehicleCode(typeName: String, id: VehicleID) -> String {
        let prefix = typeName.prefix(3).uppercased()
        return "\(prefix)-\(String(format: "%02d", id.rawValue))"
    }
}

extension Color {
    /// Parses "#RRGGBB". Falls back to accentColor-ish blue on bad input.
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self = .blue
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension LogEntry {
    /// Player-facing log line. Uses catalog for display names.
    func message(catalog: GameCatalog) -> String {
        func cityName(_ id: CityID) -> String { catalog.city(id)?.name ?? id.rawValue }
        switch event {
        case .companyFounded(let city):
            return String(localized: "Company founded in \(cityName(city)).")
        case .vehiclePurchased(let typeID, let city):
            let typeName = catalog.vehicleType(typeID)?.name ?? typeID.rawValue
            return String(localized: "Purchased \(String(localized: String.LocalizationValue(typeName))) in \(cityName(city)).")
        case .jobAccepted(_, let origin, let destination):
            return String(localized: "Accepted job: \(cityName(origin)) → \(cityName(destination)).")
        case .jobPickedUp(_, let origin, let destination):
            return String(localized: "Picked up cargo: \(cityName(origin)) → \(cityName(destination)).")
        case .jobDelivered(_, let destination, let revenue, let cost):
            return String(localized: "Delivered in \(cityName(destination)): \(Format.money(revenue)) revenue, \(Format.money(cost)) cost.")
        case .contractSigned(_, let origin, let destination):
            return String(localized: "Signed contract: \(cityName(origin)) → \(cityName(destination)).")
        case .vehicleAssignedToRoute(let vehicleID, _):
            return String(localized: "Vehicle #\(vehicleID.rawValue) assigned to a route.")
        case .vehicleUnassignedFromRoute(let vehicleID, _):
            return String(localized: "Vehicle #\(vehicleID.rawValue) released from its route.")
        case .routeStarted:
            return String(localized: "Route started.")
        case .routeStopped:
            return String(localized: "Route stopped.")
        case .routeShipmentDelivered(_, _, let destination, let revenue):
            return String(localized: "Route delivery in \(cityName(destination)): \(Format.money(revenue)) revenue.")
        case .routeShipmentSkipped:
            return String(localized: "A route pickup was skipped (cargo missing or vehicle full).")
        case .contractShipmentMissed(_, let penalty):
            return String(localized: "Contract shipment missed. Compensation paid: \(Format.money(penalty)).")
        case .contractEnded(_, let completed, let missed):
            return String(localized: "Contract ended: \(completed) delivered, \(missed) missed.")
        }
    }
}
