//
//  GameCatalog+Derivation.swift
//  Goods&Glory
//
//  Content the catalog computes rather than stores: trading firms and the
//  persistent freight lanes between them.
//

import Foundation

extension GameCatalog {
    // MARK: - Firm derivation

    /// Deterministically turns every city-market supply/demand entry into a
    /// named trading firm. No authored firm data and no save state: the same
    /// catalog always yields the same firms.
    static func deriveFirms(
        cities: [CityDefinition],
        cityMarkets: [CityMarketProfile],
        pools: FirmNamePools
    ) -> [Firm] {
        guard !pools.stems.isEmpty else { return [] }
        var firms: [Firm] = []
        for city in cities.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard let market = cityMarkets.first(where: { $0.cityID == city.id }) else { continue }
            var usedStems: Set<String> = []

            func stem(for product: ProductID, role: FirmRole) -> String {
                let hash = SeedDerivation.seed(
                    0, "firm_stem",
                    .string(city.id.rawValue), .string(product.rawValue), .string(role.rawValue)
                )
                var index = Int(hash % UInt64(pools.stems.count))
                // Linear probe so firm names stay unique within one city.
                for _ in 0..<pools.stems.count {
                    let candidate = pools.stems[index]
                    if !usedStems.contains(candidate) {
                        usedStems.insert(candidate)
                        return candidate
                    }
                    index = (index + 1) % pools.stems.count
                }
                return pools.stems[index]
            }

            func suffix(for product: ProductID, role: FirmRole, from list: [String]) -> String {
                guard !list.isEmpty else { return "" }
                let hash = SeedDerivation.seed(
                    0, "firm_suffix",
                    .string(city.id.rawValue), .string(product.rawValue), .string(role.rawValue)
                )
                return list[Int(hash % UInt64(list.count))]
            }

            for entry in market.supply {
                let name = "\(stem(for: entry.productID, role: .supplier)) \(suffix(for: entry.productID, role: .supplier, from: pools.supplierSuffixes))"
                firms.append(Firm(
                    id: firmID(city: city.id, product: entry.productID, role: .supplier),
                    cityID: city.id,
                    productID: entry.productID,
                    role: .supplier,
                    name: name.trimmingCharacters(in: .whitespaces)
                ))
            }
            for entry in market.demand {
                let name = "\(stem(for: entry.productID, role: .receiver)) \(suffix(for: entry.productID, role: .receiver, from: pools.receiverSuffixes))"
                firms.append(Firm(
                    id: firmID(city: city.id, product: entry.productID, role: .receiver),
                    cityID: city.id,
                    productID: entry.productID,
                    role: .receiver,
                    name: name.trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        return firms
    }

    // MARK: - Freight lane derivation

    /// Structural rules of lane derivation (counts are rules; rates and
    /// falloff are balance values in `economy.lanes`).
    static let laneDestinationsPerProduct = 2
    static let maximumLanesPerCity = 16
    /// Small cities keep their top lanes even below the rate floor, so no
    /// catalog city is ever laneless.
    static let minimumLanesPerCity = 3

    /// Deterministically derives persistent firm→firm freight lanes from city
    /// markets. Same catalog, same lanes: no authored lane data, no save state.
    ///
    /// Per origin city: the city's daily outbound budget (population-scaled) is
    /// split across supply products by squared weight (concentration — the
    /// city's signature products carry most of its freight), then each product
    /// budget is split across the best-scoring reachable destinations
    /// (demand weight with distance falloff). Low-rate candidates are dropped.
    static func deriveLanes(
        cities: [CityDefinition],
        cityMarketsByID: [CityID: CityMarketProfile],
        economy: EconomyConfig,
        cityDistances: [CityID: [CityID: Double]]
    ) -> [FreightLane] {
        let config = economy.lanes
        var lanes: [FreightLane] = []
        for origin in cities.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard let market = cityMarketsByID[origin.id], !market.supply.isEmpty else { continue }
            let distances = cityDistances[origin.id] ?? [:]
            let cityBudget = Double(origin.population) / 100_000
                * Double(config.cityOutboundKgPerDayPer100k)
            let weightSquaredSum = market.supply.reduce(0.0) {
                $0 + Double($1.weight) * Double($1.weight)
            }
            guard weightSquaredSum > 0 else { continue }

            var candidates: [FreightLane] = []
            for entry in market.supply {
                let productBudget = cityBudget
                    * Double(entry.weight) * Double(entry.weight) / weightSquaredSum
                var scored: [(city: CityID, score: Double)] = []
                for (destination, km) in distances where destination != origin.id {
                    guard let demand = cityMarketsByID[destination]?.demand
                        .first(where: { $0.productID == entry.productID }) else { continue }
                    let score = Double(demand.weight)
                        / (1 + km / Double(config.distanceHalfWeightKm))
                    scored.append((destination, score))
                }
                scored.sort {
                    $0.score == $1.score
                        ? $0.city.rawValue < $1.city.rawValue
                        : $0.score > $1.score
                }
                let chosen = scored.prefix(laneDestinationsPerProduct)
                let scoreSum = chosen.reduce(0.0) { $0 + $1.score }
                guard scoreSum > 0 else { continue }
                for pick in chosen {
                    let rate = Int((productBudget * pick.score / scoreSum).rounded())
                    candidates.append(FreightLane(
                        id: LaneID("\(origin.id.rawValue).\(entry.productID.rawValue).\(pick.city.rawValue)"),
                        originCityID: origin.id,
                        destinationCityID: pick.city,
                        productID: entry.productID,
                        originFirmID: firmID(city: origin.id, product: entry.productID, role: .supplier),
                        destinationFirmID: firmID(city: pick.city, product: entry.productID, role: .receiver),
                        baseRatePerDayKg: rate
                    ))
                }
            }

            candidates.sort {
                $0.baseRatePerDayKg == $1.baseRatePerDayKg
                    ? $0.id.rawValue < $1.id.rawValue
                    : $0.baseRatePerDayKg > $1.baseRatePerDayKg
            }
            var kept: [FreightLane] = []
            for candidate in candidates.prefix(maximumLanesPerCity) where candidate.baseRatePerDayKg >= 1 {
                if kept.count < minimumLanesPerCity
                    || candidate.baseRatePerDayKg >= config.minimumRatePerDayKg {
                    kept.append(candidate)
                }
            }
            lanes.append(contentsOf: kept)
        }
        return lanes
    }

    static func uniqueIndex<T, ID: Hashable>(
        _ items: [T], id: KeyPath<T, ID>, label: String
    ) throws -> [ID: T] {
        var index: [ID: T] = [:]
        for item in items {
            let key = item[keyPath: id]
            guard index[key] == nil else {
                throw CatalogError.validationFailure("duplicate \(label) id: \(key)")
            }
            index[key] = item
        }
        return index
    }

}
