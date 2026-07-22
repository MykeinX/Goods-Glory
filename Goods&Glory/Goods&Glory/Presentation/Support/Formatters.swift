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

    /// Human-scale duration. Nobody reads "600 h" as five weeks, so anything
    /// past a day is expressed in days, and past two weeks in weeks.
    static func duration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let mins = clamped % 60

        if clamped >= 14 * 24 * 60 {
            let weeks = Double(clamped) / Double(7 * 24 * 60)
            return String(localized: "\(weeks.formatted(.number.precision(.fractionLength(0...1)))) wk")
        }
        if clamped >= 24 * 60 {
            let days = clamped / (24 * 60)
            let leftoverHours = (clamped % (24 * 60)) / 60
            if leftoverHours == 0 { return String(localized: "\(days) d") }
            return String(localized: "\(days) d \(leftoverHours) h")
        }
        if hours == 0 { return String(localized: "\(mins) min") }
        if mins == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(mins) min")
    }

    /// Coarse duration for cards where precision is noise: "3 d", "8 h".
    static func shortDuration(minutes: Int) -> String {
        let clamped = max(0, minutes)
        if clamped >= 24 * 60 {
            return String(localized: "\(clamped / (24 * 60)) d")
        }
        if clamped >= 60 { return String(localized: "\(clamped / 60) h") }
        return String(localized: "\(clamped) min")
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

    /// Player-facing name of a facility module.
    static func moduleName(_ kind: FacilityModuleKind) -> String {
        switch kind {
        case .office: return String(localized: "Office")
        case .warehouse: return String(localized: "Warehouse")
        case .dock: return String(localized: "Loading docks")
        case .racking: return String(localized: "Racking")
        case .forklift: return String(localized: "Forklifts")
        }
    }

    /// What installing this module lets the site do.
    static func moduleSummary(_ kind: FacilityModuleKind) -> String {
        switch kind {
        case .office: return String(localized: "Your presence here: sign contracts, and build the rest of the site")
        case .warehouse: return String(localized: "Store and consolidate freight — and take loading docks")
        case .dock: return String(localized: "Warehouse equipment: load and unload trucks faster")
        case .racking: return String(localized: "Shelving: more tonnage in the same warehouse")
        case .forklift: return String(localized: "Dock equipment: faster still on every load")
        }
    }

    static func moduleSymbol(_ kind: FacilityModuleKind) -> String {
        switch kind {
        case .office: return "building.2.fill"
        case .warehouse: return "shippingbox.fill"
        case .dock: return "arrow.left.arrow.right.square.fill"
        case .racking: return "square.grid.3x3.fill"
        case .forklift: return "bolt.fill"
        }
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
        case .facilityConstructionStarted(_, let kind, let city, let level):
            return String(localized: "\(Format.moduleName(kind)) level \(level) started in \(cityName(city)).")
        case .facilityCompleted(_, let kind, let city, let level):
            return String(localized: "\(Format.moduleName(kind)) in \(cityName(city)) is now open at level \(level).")
        case .facilityDemolished(let kind, let city):
            return String(localized: "\(Format.moduleName(kind)) in \(cityName(city)) was removed.")
        case .cargoStored(let city, let parcels, let massKg):
            return String(localized: "Stored \(parcels) parcel(s) (\(Format.mass(kg: massKg))) in \(cityName(city)).")
        case .cargoLoadedFromWarehouse(let city, let parcels, let massKg):
            return String(localized: "Collected \(parcels) parcel(s) (\(Format.mass(kg: massKg))) from the \(cityName(city)) warehouse.")
        case .warehouseFull(let city, let refusedParcels):
            return String(localized: "The \(cityName(city)) warehouse is full — \(refusedParcels) parcel(s) stayed on the vehicle.")
        case .contractCancellationRequested:
            return String(localized: "Contract closing — no new loads, committed freight still runs.")
        case .routeNeedsReview:
            return String(localized: "A contract ended — its route keeps running on spot freight. Edit the dead stops.")
        }
    }
}
