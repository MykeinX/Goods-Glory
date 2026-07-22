//
//  SimulationEngine+DebugFormat.swift
//  Goods&Glory
//
//  Terse formatters for the balancing ledger. Shared by every engine file that
//  records a line, which is why they live on their own rather than inside one
//  feature's extension.
//

import Foundation

extension SimulationEngine {
    /// Terse formatters for the balancing log. Density is the feature: every
    /// character spent on decoration is a line the reader has to scroll past.
    func short(_ city: CityID) -> String {
        let raw = city.rawValue
        // Strip the country namespace: "us_kansas_city" reads as "kansas_city".
        let name = raw.contains("_") ? String(raw.drop(while: { $0 != "_" }).dropFirst()) : raw
        return String(name.prefix(12))
    }

    func money(_ amount: Money) -> String { "$\(amount)" }
    func rate(_ value: Double) -> String { String(format: "$%.2f", value) }
    func km(_ value: Double) -> String { "\(Int(value.rounded()))km" }
    func kg(_ value: Int) -> String {
        value >= 1_000 ? String(format: "%.1ft", Double(value) / 1_000) : "\(value)kg"
    }
    func pct(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

}
