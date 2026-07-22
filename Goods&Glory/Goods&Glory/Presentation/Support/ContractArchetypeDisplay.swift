//
//  ContractArchetypeDisplay.swift
//  Goods&Glory
//
//  The label and colour of a contract archetype, in one place. This switch had
//  been written three times and the copies had already drifted apart on the
//  multi-drop colour.
//

import SwiftUI

enum ContractArchetypeDisplay {
    static func label(_ archetype: ContractArchetype) -> String {
        switch archetype {
        case .laneRecurring: String(localized: "Lane")
        case .bulkPeriodic: String(localized: "Bulk")
        case .evergreen: String(localized: "Ongoing")
        case .multiDrop: String(localized: "Multi-drop")
        }
    }

    static func color(_ archetype: ContractArchetype) -> Color {
        switch archetype {
        case .laneRecurring: Theme.mint
        case .bulkPeriodic: Theme.coral
        case .evergreen: Theme.sky
        case .multiDrop: Theme.violet
        }
    }
}
