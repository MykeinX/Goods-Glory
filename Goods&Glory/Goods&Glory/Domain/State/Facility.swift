//
//  Facility.swift
//  Goods&Glory
//
//  Company buildings. Two kinds with strictly separate jobs (GDD "Tesisler"):
//
//  - branch:    commercial presence. Unlocks contract business in its city and
//               scales how many lanes that city offers. Stores no cargo.
//  - warehouse: physical cargo node. Accepts, holds and dispatches freight,
//               enabling multi-stage transport instead of point-to-point hauls.
//
//  Construction is not instant: a facility is inert until `operationalAt`.
//

import Foundation

enum FacilityKind: String, Codable, Hashable, Sendable, CaseIterable {
    case branch
    case warehouse
}

struct Facility: Codable, Identifiable, Sendable {
    let id: FacilityID
    let cityID: CityID
    let kind: FacilityKind
    var level: Int
    /// The founding branch. Always level 1+, cannot be demolished.
    let isHeadquarters: Bool
    let foundedAt: GameTime
    /// Construction completion. Before this the facility grants nothing.
    var operationalAt: GameTime
    /// Set while a level upgrade is under construction. The facility keeps
    /// serving at its current level until the upgrade lands.
    var upgradingTo: Int?
    var upgradeEndsAt: GameTime?
    /// Guards the one-off "construction finished" notice. Kept on the facility
    /// rather than inferred from the log, which is trimmed to a bounded size.
    var hasAnnouncedCompletion: Bool = false

    func isOperational(at clock: GameTime) -> Bool {
        operationalAt <= clock
    }

    var isUpgrading: Bool { upgradingTo != nil }
}

// MARK: - State queries

extension GameState {
    func facility(_ id: FacilityID) -> Facility? {
        facilities.first { $0.id == id }
    }

    func facility(kind: FacilityKind, in cityID: CityID) -> Facility? {
        facilities.first { $0.cityID == cityID && $0.kind == kind }
    }

    func branch(in cityID: CityID) -> Facility? {
        facility(kind: .branch, in: cityID)
    }

    func warehouse(in cityID: CityID) -> Facility? {
        facility(kind: .warehouse, in: cityID)
    }

    /// Contract business requires a finished branch. The HQ branch is created
    /// at founding and is operational immediately.
    func hasOperationalBranch(in cityID: CityID) -> Bool {
        branch(in: cityID)?.isOperational(at: clock) ?? false
    }

    func hasOperationalWarehouse(in cityID: CityID) -> Bool {
        warehouse(in: cityID)?.isOperational(at: clock) ?? false
    }

    /// Cities where the player may sign contracts, in stable catalog order.
    var contractCities: [CityID] {
        facilities
            .filter { $0.kind == .branch && $0.isOperational(at: clock) }
            .map(\.cityID)
    }
}
