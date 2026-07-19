//
//  FacilityEconomics.swift
//  Goods&Glory
//
//  Resolves facility build cost, build time, upkeep and capacity for a concrete
//  city. Nothing here is a flat number: every value is the authored base value
//  from economy.json scaled by that city's own catalog data (K-009 — no authored
//  city roles, everything derives from population, cost index and access flags).
//
//      siteFactor = (costIndex / 1000)              regional price level (BEA RPP)
//                 x (0.75 + 0.65 * populationNorm)   metro land scarcity
//                 x (1 + 0.04 * accessFlagCount)     port / rail / air premium
//
//  Band is roughly 0.60x - 1.85x across the current US slice, so the same
//  warehouse costs about three times more in New York than in Memphis.
//

import Foundation

/// Fully resolved economics of one facility level in one city.
struct FacilityQuote: Equatable, Sendable {
    let kind: FacilityKind
    let cityID: CityID
    let level: Int
    let cost: Money
    let buildMinutes: Int
    let upkeepPerDay: Money
    let storage: LoadSize
    let docks: Int
    /// Handling duration multiplier, 1.0 = catalog baseline.
    let handlingFactor: Double
    /// Multiplier applied to a city's contract offer slot count (branch only).
    let contractSlotFactor: Double
    /// Extra payout fraction on lanes touching this city (branch only).
    let lanePremium: Double
}

enum FacilityEconomics {
    // MARK: - Site factor

    private static let populationNormLower: Double = 300_000
    private static let populationNormUpper: Double = 9_000_000

    /// Per-city multiplier applied to every authored base value.
    static func siteFactor(for city: CityDefinition) -> Double {
        let priceLevel = Double(city.costIndex) / 1000
        let popNorm = normalized(
            Double(city.population),
            min: populationNormLower,
            max: populationNormUpper
        )
        let landScarcity = 0.75 + 0.65 * popNorm
        let accessCount = [
            city.hasSeaPortAccess,
            city.hasRailFreightAccess,
            city.hasAirCargoAccess
        ].filter { $0 }.count
        let accessPremium = 1 + 0.04 * Double(accessCount)
        return priceLevel * landScarcity * accessPremium
    }

    /// Build duration scales more gently than money: permits and construction
    /// take longer in dense metros but never triple.
    static func buildTimeFactor(for city: CityDefinition) -> Double {
        let popNorm = normalized(
            Double(city.population),
            min: populationNormLower,
            max: populationNormUpper
        )
        return 0.85 + 0.3 * popNorm
    }

    // MARK: - Quotes

    static func quote(
        kind: FacilityKind,
        level: Int,
        city: CityDefinition,
        config: FacilityConfig
    ) -> FacilityQuote? {
        guard let spec = config.spec(kind: kind, level: level) else { return nil }
        let site = siteFactor(for: city)
        let time = buildTimeFactor(for: city)
        return FacilityQuote(
            kind: kind,
            cityID: city.id,
            level: level,
            cost: Money((Double(spec.buildCost) * site).rounded()),
            buildMinutes: Int((Double(spec.buildDays * GameState.minutesPerDay) * time).rounded()),
            upkeepPerDay: Money((Double(spec.upkeepPerDay) * site).rounded()),
            storage: LoadSize(massKg: spec.storageMassKg, volumeM3: spec.storageVolumeM3),
            docks: spec.docks,
            handlingFactor: Double(spec.handlingPercent) / 100,
            contractSlotFactor: Double(spec.contractSlotPercent) / 100,
            lanePremium: Double(spec.lanePremiumPercent) / 100
        )
    }

    /// Upgrading pays the difference in base cost, never the full new level.
    static func upgradeQuote(
        from currentLevel: Int,
        kind: FacilityKind,
        city: CityDefinition,
        config: FacilityConfig
    ) -> FacilityQuote? {
        let nextLevel = currentLevel + 1
        guard let next = config.spec(kind: kind, level: nextLevel),
              let current = config.spec(kind: kind, level: currentLevel),
              var quote = quote(kind: kind, level: nextLevel, city: city, config: config) else {
            return nil
        }
        let site = siteFactor(for: city)
        let delta = max(0, next.buildCost - current.buildCost)
        let deltaDays = max(1, next.buildDays - current.buildDays)
        quote = FacilityQuote(
            kind: quote.kind,
            cityID: quote.cityID,
            level: quote.level,
            cost: Money((Double(delta) * site).rounded()),
            buildMinutes: Int(
                (Double(deltaDays * GameState.minutesPerDay) * buildTimeFactor(for: city)).rounded()
            ),
            upkeepPerDay: quote.upkeepPerDay,
            storage: quote.storage,
            docks: quote.docks,
            handlingFactor: quote.handlingFactor,
            contractSlotFactor: quote.contractSlotFactor,
            lanePremium: quote.lanePremium
        )
        return quote
    }

    static func normalized(_ value: Double, min lower: Double, max upper: Double) -> Double {
        guard upper > lower else { return 0.5 }
        return Swift.min(1, Swift.max(0, (value - lower) / (upper - lower)))
    }
}
