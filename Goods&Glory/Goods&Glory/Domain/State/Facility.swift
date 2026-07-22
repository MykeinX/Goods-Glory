//
//  Facility.swift
//  Goods&Glory
//
//  One site per city, specialised by the modules installed on it (GDD K-011).
//
//  "Branch" and "warehouse" are no longer separate buildings competing for the
//  same plot — they are capabilities of the same site:
//
//  - office:    commercial presence. Unlocks contract business in its city and
//               scales how many lanes that city offers. Holds no cargo.
//  - warehouse: physical cargo node. Accepts, holds and dispatches freight,
//               enabling multi-stage transport instead of point-to-point hauls.
//  - dock:      concurrent handling. Raises how fast the site turns vehicles
//               around, independently of how much it can store.
//
//  Two sites at the same module level can therefore have completely different
//  characters — a fast cross-dock and a deep store — which is where facility
//  strategy comes from. Each module builds and upgrades on its own clock; a
//  module grants nothing until its `operationalAt`.
//

import Foundation

enum FacilityModuleKind: String, Codable, Hashable, Sendable, CaseIterable {
    case office
    case warehouse
    case dock
    case racking
    case forklift

    /// Display order on the facility screen: commercial, then storage, then
    /// throughput — the order a site is usually grown in, each followed by the
    /// equipment that goes into it.
    static let installOrder: [FacilityModuleKind] = [
        .office, .warehouse, .racking, .dock, .forklift
    ]

    /// Equipment bolted into a building rather than a building of its own.
    /// Purely a presentation and pricing distinction: mechanically it is the
    /// same object with the same levels, which is why there is no second
    /// install/upgrade/remove path to keep in step with this one.
    var isEquipment: Bool {
        switch self {
        case .office, .warehouse, .dock: false
        case .racking, .forklift: true
        }
    }

    /// What this module is built onto.
    ///
    /// A site is not three interchangeable purchases. The office is the company's
    /// presence in the city and everything else stands next to it; a warehouse
    /// needs that presence to run it; loading docks are warehouse equipment and
    /// mean nothing without a warehouse to load into. Offering them separately
    /// let a player buy docks in a city where the company had nothing at all.
    var requires: FacilityModuleKind? {
        switch self {
        case .office: nil
        case .warehouse: .office
        case .dock: .warehouse
        // Racking is the warehouse's own shelving; a forklift belongs to the
        // dock it works. Neither means anything standing on bare ground.
        case .racking: .warehouse
        case .forklift: .dock
        }
    }

    /// Modules that would be left standing on nothing if this one went.
    var dependents: [FacilityModuleKind] {
        Self.allCases.filter { $0.requires == self }
    }

    /// How deep in the site tree this sits. Office 0, warehouse 1, racking 2.
    var depth: Int {
        guard let requires else { return 0 }
        return requires.depth + 1
    }
}

struct FacilityModule: Codable, Hashable, Sendable {
    let kind: FacilityModuleKind
    var level: Int
    /// Construction completion. Before this the module grants nothing.
    var operationalAt: GameTime
    /// Set while a level upgrade is under construction. The module keeps
    /// serving at its current level until the upgrade lands.
    var upgradingTo: Int?
    var upgradeEndsAt: GameTime?
    /// Guards the one-off "construction finished" notice.
    var hasAnnouncedCompletion: Bool = false

    func isOperational(at clock: GameTime) -> Bool { operationalAt <= clock }
    var isUpgrading: Bool { upgradingTo != nil }
}

struct Facility: Codable, Identifiable, Sendable {
    let id: FacilityID
    let cityID: CityID
    /// The founding site. Cannot be demolished.
    let isHeadquarters: Bool
    let foundedAt: GameTime
    var modules: [FacilityModule]

    func module(_ kind: FacilityModuleKind) -> FacilityModule? {
        modules.first { $0.kind == kind }
    }

    func operationalModule(_ kind: FacilityModuleKind, at clock: GameTime) -> FacilityModule? {
        module(kind).flatMap { $0.isOperational(at: clock) ? $0 : nil }
    }

    /// A site with nothing finished yet is still under construction.
    func isOperational(at clock: GameTime) -> Bool {
        modules.contains { $0.isOperational(at: clock) }
    }
}

// MARK: - State queries

extension GameState {
    func facility(_ id: FacilityID) -> Facility? {
        facilities.first { $0.id == id }
    }

    /// The company's site in a city, if it has one. One site per city.
    func facility(in cityID: CityID) -> Facility? {
        facilities.first { $0.cityID == cityID }
    }

    func module(_ kind: FacilityModuleKind, in cityID: CityID) -> FacilityModule? {
        facility(in: cityID)?.module(kind)
    }

    /// Contract business requires a finished office. The HQ office is created
    /// at founding and is operational immediately.
    func hasOperationalOffice(in cityID: CityID) -> Bool {
        facility(in: cityID)?.operationalModule(.office, at: clock) != nil
    }

    func hasOperationalWarehouse(in cityID: CityID) -> Bool {
        facility(in: cityID)?.operationalModule(.warehouse, at: clock) != nil
    }

    /// The storage-capable site in a city, or nil when there is none yet.
    /// Warehouse route tasks address the site; the module is what makes it
    /// able to accept cargo.
    func warehouseSite(in cityID: CityID) -> Facility? {
        guard let facility = facility(in: cityID),
              facility.operationalModule(.warehouse, at: clock) != nil else { return nil }
        return facility
    }

    /// Cities where the player may sign contracts, in stable catalog order.
    var contractCities: [CityID] {
        facilities
            .filter { $0.operationalModule(.office, at: clock) != nil }
            .map(\.cityID)
    }
}
