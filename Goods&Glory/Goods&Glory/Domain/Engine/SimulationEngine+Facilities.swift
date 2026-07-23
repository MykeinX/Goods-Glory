//
//  SimulationEngine+Facilities.swift
//  Goods&Glory
//
//  Sites and their modules: quotes, install, upgrade, remove, and the
//  construction clock. A city holds one site; modules decide what it does.
//

import Foundation

extension SimulationEngine {
    // MARK: - Facilities

    /// Price, duration and capacity of a module level in one city. Read-only,
    /// used by both the command path and the UI so the player is never quoted
    /// a number the engine will not honour.
    func quote(kind: FacilityModuleKind, level: Int, city cityID: CityID) -> FacilityQuote? {
        guard let city = catalog.city(cityID) else { return nil }
        return FacilityEconomics.quote(
            kind: kind,
            level: level,
            city: city,
            config: catalog.economy.facilities
        )
    }

    func upgradeQuote(for module: FacilityModule, in cityID: CityID) -> FacilityQuote? {
        guard let city = catalog.city(cityID) else { return nil }
        return FacilityEconomics.upgradeQuote(
            from: module.level,
            kind: module.kind,
            city: city,
            config: catalog.economy.facilities
        )
    }

    /// Installs a module on the city's site, creating the site if this is the
    /// first one. A city holds one site; what it can do is decided by which
    /// modules stand on it.
    func installModule(
        kind: FacilityModuleKind,
        cityID: CityID,
        state: inout GameState
    ) throws {
        guard catalog.city(cityID) != nil else { throw CommandError.unknownReference }
        guard state.module(kind, in: cityID) == nil else {
            throw CommandError.facilityAlreadyExists
        }
        // Modules stand on each other, not side by side. The prerequisite only
        // has to be *started*, not finished: work on one site can overlap, and
        // making the player wait out the office before ordering the warehouse
        // would be bureaucracy, not logistics.
        if let required = kind.requires {
            guard state.module(required, in: cityID) != nil else {
                throw required == .office
                    ? CommandError.officeRequired
                    : CommandError.warehouseRequired
            }
        }
        guard let quote = quote(kind: kind, level: 1, city: cityID) else {
            throw CommandError.unknownReference
        }
        guard state.cash >= quote.cost else {
            throw CommandError.insufficientFunds(required: quote.cost)
        }

        state.cash -= quote.cost
        state.stats.totalCost += quote.cost
        let module = FacilityModule(
            kind: kind,
            level: 1,
            operationalAt: state.clock + quote.buildMinutes,
            upgradingTo: nil,
            upgradeEndsAt: nil
        )
        let facilityID: FacilityID
        if let index = state.facilities.firstIndex(where: { $0.cityID == cityID }) {
            state.facilities[index].modules.append(module)
            facilityID = state.facilities[index].id
        } else {
            let facility = Facility(
                id: FacilityID(rawValue: state.issueID()),
                cityID: cityID,
                isHeadquarters: false,
                foundedAt: state.clock,
                modules: [module]
            )
            state.facilities.append(facility)
            facilityID = facility.id
        }
        state.appendLog(.facilityConstructionStarted(
            facilityID: facilityID,
            kind: kind,
            city: cityID,
            level: 1
        ))
        state.recordDebug(
            .capital,
            delta: -quote.cost,
            "BUILD \(kind.rawValue) \(short(cityID)) lvl1 \(money(quote.cost)) "
                + "upkeep \(money(quote.upkeepPerDay))/d ready in \(quote.buildMinutes / 1440)d"
        )
    }

    func upgradeModule(
        kind: FacilityModuleKind,
        cityID: CityID,
        state: inout GameState
    ) throws {
        guard let facilityIndex = state.facilities.firstIndex(where: { $0.cityID == cityID }),
              let moduleIndex = state.facilities[facilityIndex].modules
                .firstIndex(where: { $0.kind == kind }) else {
            throw CommandError.unknownReference
        }
        let module = state.facilities[facilityIndex].modules[moduleIndex]
        guard module.isOperational(at: state.clock), !module.isUpgrading else {
            throw CommandError.facilityNotAvailable
        }
        guard module.level < catalog.economy.facilities.maxLevel(for: kind),
              let quote = upgradeQuote(for: module, in: cityID) else {
            throw CommandError.facilityNotAvailable
        }
        guard state.cash >= quote.cost else {
            throw CommandError.insufficientFunds(required: quote.cost)
        }

        state.cash -= quote.cost
        state.stats.totalCost += quote.cost
        state.facilities[facilityIndex].modules[moduleIndex].upgradingTo = module.level + 1
        state.facilities[facilityIndex].modules[moduleIndex].upgradeEndsAt =
            state.clock + quote.buildMinutes
        state.appendLog(.facilityConstructionStarted(
            facilityID: state.facilities[facilityIndex].id,
            kind: kind,
            city: cityID,
            level: module.level + 1
        ))
        state.recordDebug(
            .capital,
            delta: -quote.cost,
            "UPGRD \(kind.rawValue) \(short(cityID)) →lvl\(module.level + 1) \(money(quote.cost))"
        )
    }

    /// Removes a module. The site itself disappears with its last module.
    func removeModule(
        kind: FacilityModuleKind,
        cityID: CityID,
        state: inout GameState
    ) throws {
        guard let facilityIndex = state.facilities.firstIndex(where: { $0.cityID == cityID }),
              state.facilities[facilityIndex].module(kind) != nil else {
            throw CommandError.unknownReference
        }
        let facility = state.facilities[facilityIndex]
        // The founding office is the company's legal home; it does not go.
        guard !(facility.isHeadquarters && kind == .office) else {
            throw CommandError.cannotDemolishHeadquarters
        }
        if kind == .warehouse {
            guard state.shipments(storedIn: facility.id).isEmpty else {
                throw CommandError.warehouseNotEmpty
            }
        }
        // Pull the office out from under a warehouse and the site is left with
        // equipment nobody runs. Clear the dependents first.
        if let standing = kind.dependents.first(where: { facility.module($0) != nil }) {
            throw CommandError.dependentModuleExists(standing)
        }
        state.facilities[facilityIndex].modules.removeAll { $0.kind == kind }
        if state.facilities[facilityIndex].modules.isEmpty {
            state.facilities.remove(at: facilityIndex)
        }
        state.appendLog(.facilityDemolished(kind: kind, city: cityID))
    }

    /// Completes construction and upgrades whose time has come. Called from the
    /// event loop so partial and whole `advance` calls land identically.
    func completeFinishedConstruction(state: inout GameState) {
        for facilityIndex in state.facilities.indices {
            let isHeadquarters = state.facilities[facilityIndex].isHeadquarters
            let facilityID = state.facilities[facilityIndex].id
            let cityID = state.facilities[facilityIndex].cityID
            for moduleIndex in state.facilities[facilityIndex].modules.indices {
                let module = state.facilities[facilityIndex].modules[moduleIndex]
                if module.operationalAt <= state.clock, !module.hasAnnouncedCompletion {
                    state.facilities[facilityIndex].modules[moduleIndex]
                        .hasAnnouncedCompletion = true
                    // The free HQ office exists from minute zero; not news.
                    if !(isHeadquarters && module.kind == .office) {
                        state.appendLog(.facilityCompleted(
                            facilityID: facilityID,
                            kind: module.kind,
                            city: cityID,
                            level: module.level
                        ))
                    }
                }
                guard let target = module.upgradingTo,
                      let endsAt = module.upgradeEndsAt,
                      endsAt <= state.clock else { continue }
                state.facilities[facilityIndex].modules[moduleIndex].level = target
                state.facilities[facilityIndex].modules[moduleIndex].upgradingTo = nil
                state.facilities[facilityIndex].modules[moduleIndex].upgradeEndsAt = nil
                state.appendLog(.facilityCompleted(
                    facilityID: facilityID,
                    kind: module.kind,
                    city: cityID,
                    level: target
                ))
            }
        }
    }

    /// Daily upkeep of every standing facility, scaled by its city.
    func facilityUpkeepPerDay(state: GameState) -> Money {
        state.facilities.reduce(0) { total, facility in
            total + facility.modules.reduce(0) { moduleTotal, module in
                moduleTotal + (quote(
                    kind: module.kind, level: module.level, city: facility.cityID
                )?.upkeepPerDay ?? 0)
            }
        }
    }

    /// Office payout bonus on lanes touching a city: the HQ home-field premium
    /// plus whatever a high-level office adds there.
    func branchLanePremium(city cityID: CityID, state: GameState) -> Double {
        var premium = 0.0
        if cityID == state.config.hqCity {
            premium += Double(catalog.economy.hqLanePremiumPercent) / 100
        }
        if let office = state.facility(in: cityID)?.operationalModule(.office, at: state.clock),
           let quote = quote(kind: .office, level: office.level, city: cityID) {
            premium += quote.lanePremium
        }
        return premium
    }

    /// Total payout multiplier for a lane, counting both endpoints.
    func lanePremiumFactor(origin: CityID, destination: CityID, state: GameState) -> Double {
        1 + branchLanePremium(city: origin, state: state)
            + branchLanePremium(city: destination, state: state)
    }

}
