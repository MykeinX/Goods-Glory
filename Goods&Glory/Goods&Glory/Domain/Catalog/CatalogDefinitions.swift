//
//  CatalogDefinitions.swift
//  Goods&Glory
//
//  Codable definitions loaded from bundled JSON. Content, balance values and
//  player-visible names live in data; rules and invariants live in code.
//  Runtime state is never written back into these definitions.
//

import Foundation

struct CityDefinition: Codable, Identifiable, Sendable {
    let id: CityID
    /// Entry point from the city into the canonical road graph.
    let roadNodeID: RoadNodeID
    /// Proper noun; not localized.
    let name: String
    let country: String
    let latitude: Double
    let longitude: Double
    /// Addressable population baseline for market demand. Every catalog city
    /// must use the same documented market/service-area definition.
    let population: Int
    /// City-level access flags; detailed terminals belong to future mode graphs.
    /// Rail: Class I freight with local yards/intermodal in the metro.
    /// Air: Significant dedicated freighter / express-hub cargo role.
    /// Sea: Commercial deep-draft coastal/estuarine or Great Lakes port.
    let hasRailFreightAccess: Bool
    let hasAirCargoAccess: Bool
    let hasSeaPortAccess: Bool
    /// Local cost proxy used by gameplay formulas. 1000 means the shared baseline.
    let costIndex: UInt16
    /// Static urban traffic proxy. 1000 means free-flow travel time; runtime
    /// time-of-day and event effects belong in simulation state.
    let trafficDelayIndex: UInt16
    let isStarterCity: Bool

    var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }
}

enum NetworkNodeKind: String, Codable, Sendable {
    case city
    case junction
}

struct NetworkNodeDefinition: Codable, Identifiable, Sendable {
    let id: RoadNodeID
    let coordinate: GeoCoordinate
    let kind: NetworkNodeKind
    /// Present only when this node is the road entry point for a city.
    let cityID: CityID?
}

struct RoadDefinition: Codable, Identifiable, Sendable {
    let id: RoadID
    let from: RoadNodeID
    let to: RoadNodeID
    let distanceKm: Double
    /// Ordered from `from` to `to`; reverse travel reads these points backwards.
    let geometry: [GeoCoordinate]
}

/// The direction in which a vehicle traverses a road's canonical geometry.
enum RoadDirection: String, Codable, Hashable, Sendable {
    case forward
    case reverse
}

struct RoadTraversal: Hashable, Codable, Sendable {
    let roadID: RoadID
    let direction: RoadDirection
}

struct VehicleTypeDefinition: Codable, Identifiable, Sendable {
    let id: VehicleTypeID
    /// English display name; localized at presentation via String Catalog.
    let name: String
    /// SF Symbol name for UI.
    let symbol: String
    let capacity: LoadSize
    let speedKmh: Double
    let purchasePrice: Money
    /// Fuel + wear, dollars per km.
    let costPerKm: Double
    /// Driver wages, dollars per game hour while on a task.
    let driverCostPerHour: Double
}

struct ProductDefinition: Codable, Identifiable, Sendable {
    /// Generated shipment masses use this deterministic granularity.
    static let shipmentMassStepKg = 50

    let id: ProductID
    /// English display name; localized at presentation via String Catalog.
    let name: String
    /// SF Symbol name for UI.
    let symbol: String
    /// Cubic meters per metric ton; converts generated mass into volume.
    let densityM3PerTon: Double
    let minimumShipmentMassKg: Int
    let maximumShipmentMassKg: Int
}

/// Static market tendency. Runtime demand is derived by the simulation and is
/// never written back into the catalog.
struct CityProductWeight: Codable, Hashable, Sendable {
    let productID: ProductID
    let weight: UInt16
}

struct CityMarketProfile: Codable, Identifiable, Sendable {
    let cityID: CityID
    /// At most 20 entries, ordered by weight descending then product ID.
    let supply: [CityProductWeight]
    /// At most 20 entries, ordered by weight descending then product ID.
    let demand: [CityProductWeight]

    var id: CityID { cityID }
}

struct EconomyConfig: Codable, Sendable {
    let startingCash: Money
    let loadingMinutes: Int
    let unloadingMinutes: Int
    /// A new batch of spot job offers is generated every interval.
    let offerGenerationIntervalMinutes: Int
    let offerLifetimeMinutes: Int
    /// Percent chance (0-100) for each additional slot after the guaranteed local offer.
    let offerChancePercent: Int
    let maxOpenOffersPerCity: Int
    /// Minimum gross profit built into a direct, loaded one-way job.
    let offerMinimumProfit: Money
    /// Gross profit percentage when it exceeds `offerMinimumProfit`.
    let offerProfitMarginPercent: Int
}
