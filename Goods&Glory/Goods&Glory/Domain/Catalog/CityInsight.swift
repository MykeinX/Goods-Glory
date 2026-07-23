//
//  CityInsight.swift
//  Goods&Glory
//
//  Presentation-facing city metrics derived from CityDefinition:
//  no authored role tags — market, competition, founding cost and perks
//  come from population, cost index and access flags.
//

import Foundation

/// A transport mode a city can be reached by. Road is universal; the rest are
/// authored capabilities. Ordered the way the UI lists them.
enum CityAccess: String, CaseIterable, Sendable {
    case road
    case rail
    case sea
    case air

    var label: String {
        switch self {
        case .road: String(localized: "Road")
        case .rail: String(localized: "Rail freight")
        case .sea: String(localized: "Sea port")
        case .air: String(localized: "Air cargo")
        }
    }
}

struct CityInsight: Equatable, Sendable {
    /// Relative market size in the current catalog, 0...1.
    let marketSizePercent: Double
    /// Static baseline competition pressure, 0...1 (rivals later replace this).
    let competitionPercent: Double
    let foundingCost: Money
    /// Transport modes serving this city. Single source for both the icon row
    /// and the text chips — the two used to read the city flags separately.
    let access: Set<CityAccess>
    /// Localized capability labels for UI chips (road omitted: every city has it).
    var perkLabels: [String] {
        CityAccess.allCases
            .filter { $0 != .road && access.contains($0) }
            .map(\.label)
    }

    private static let costIndexNormLower: Double = 800
    private static let costIndexNormUpper: Double = 1_400
    /// Founding plus a first vehicle has to leave a working buffer. At 40 the
    /// company began its first lap with a few hundred dollars, so one bad
    /// decision ended the campaign before it could teach anything.
    private static let foundingCostPerCostIndex: Int = 22

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
            access: access(for: city)
        )
    }

    private static func access(for city: CityDefinition) -> Set<CityAccess> {
        var modes: Set<CityAccess> = [.road]
        if city.hasSeaPortAccess { modes.insert(.sea) }
        if city.hasRailFreightAccess { modes.insert(.rail) }
        if city.hasAirCargoAccess { modes.insert(.air) }
        return modes
    }

    private static func normalized(_ value: Double, min lower: Double, max upper: Double) -> Double {
        guard upper > lower else { return 0.5 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}
