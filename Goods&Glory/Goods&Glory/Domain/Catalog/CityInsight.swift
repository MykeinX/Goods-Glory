//
//  CityInsight.swift
//  Goods&Glory
//
//  Presentation-facing city metrics derived from CityDefinition (K-009):
//  no authored role tags — market, competition, founding cost and perks
//  come from population, cost index and access flags.
//

import Foundation

struct CityInsight: Equatable, Sendable {
    /// Relative market size in the current catalog, 0...1.
    let marketSizePercent: Double
    /// Static baseline competition pressure, 0...1 (rivals later replace this).
    let competitionPercent: Double
    let foundingCost: Money
    /// Localized capability labels for UI chips.
    let perkLabels: [String]

    private static let costIndexNormLower: Double = 800
    private static let costIndexNormUpper: Double = 1_400
    private static let foundingCostPerCostIndex: Int = 40

    static func foundingCost(for city: CityDefinition) -> Money {
        Money(Int(city.costIndex) * foundingCostPerCostIndex)
    }

    static func make(city: CityDefinition, catalog: GameCatalog) -> CityInsight {
        let populations = catalog.cities.map(\.population)
        let popNorm = normalized(
            Double(city.population),
            min: Double(populations.min() ?? city.population),
            max: Double(populations.max() ?? city.population)
        )
        let costNorm = normalized(
            Double(city.costIndex),
            min: costIndexNormLower,
            max: costIndexNormUpper
        )
        return CityInsight(
            marketSizePercent: popNorm,
            competitionPercent: (0.55 * popNorm) + (0.45 * costNorm),
            foundingCost: foundingCost(for: city),
            perkLabels: perkLabels(for: city)
        )
    }

    private static func perkLabels(for city: CityDefinition) -> [String] {
        var labels: [String] = []
        if city.hasSeaPortAccess {
            labels.append(String(localized: "Sea port"))
        }
        if city.hasRailFreightAccess {
            labels.append(String(localized: "Rail freight"))
        }
        if city.hasAirCargoAccess {
            labels.append(String(localized: "Air cargo"))
        }
        return labels
    }

    private static func normalized(_ value: Double, min lower: Double, max upper: Double) -> Double {
        guard upper > lower else { return 0.5 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}
