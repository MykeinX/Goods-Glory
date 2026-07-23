//
//  CatalogDefinitions.swift
//  Goods&Glory
//
//  Codable definitions loaded from bundled JSON. Content, balance values and
//  player-visible names live in data; rules and invariants live in code.
//  Runtime state is never written back into these definitions.
//

import Foundation

/// Landmass grouping. Road networks do not cross between continents — freight
/// between them needs sea or air, which the vehicle catalog does not offer yet.
enum Continent: String, Codable, Sendable, CaseIterable {
    case america
    case europe
    case asia

    /// Display order for the founding screen's continent picker.
    static let pickerOrder: [Continent] = [.america, .europe, .asia]
}

struct CityDefinition: Codable, Identifiable, Sendable {
    let id: CityID
    /// Entry point from the city into the canonical road graph.
    let roadNodeID: RoadNodeID
    /// Proper noun; not localized.
    let name: String
    let country: String
    let continent: Continent
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
    /// Static urban traffic proxy. 1000 means free-lane travel time; runtime
    /// time-of-day and event effects belong in simulation state.
    let trafficDelayIndex: UInt16
    let isStarterCity: Bool

    var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }

    /// Spelled out rather than synthesized so `continent` can carry a default.
    /// Bundled content always states it; code-defined test fixtures build
    /// one-country worlds where it is noise.
    init(
        id: CityID,
        roadNodeID: RoadNodeID,
        name: String,
        country: String,
        continent: Continent = .america,
        latitude: Double,
        longitude: Double,
        population: Int,
        hasRailFreightAccess: Bool,
        hasAirCargoAccess: Bool,
        hasSeaPortAccess: Bool,
        costIndex: UInt16,
        trafficDelayIndex: UInt16,
        isStarterCity: Bool
    ) {
        self.id = id
        self.roadNodeID = roadNodeID
        self.name = name
        self.country = country
        self.continent = continent
        self.latitude = latitude
        self.longitude = longitude
        self.population = population
        self.hasRailFreightAccess = hasRailFreightAccess
        self.hasAirCargoAccess = hasAirCargoAccess
        self.hasSeaPortAccess = hasSeaPortAccess
        self.costIndex = costIndex
        self.trafficDelayIndex = trafficDelayIndex
        self.isStarterCity = isStarterCity
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
    /// Build-time path length; routing and travel time use this, not polylines.
    let distanceKm: Double
}

/// Travel direction along an undirected road edge in the routing graph.
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
    /// Insurance / ownership, dollars per game day while the vehicle is owned.
    /// Freight prices are derived from cost, not from a per-class rate: see
    /// `SimulationEngine.freightPayout`.
    let fixedCostPerDay: Double
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

/// Name material for derived trading firms. Firms themselves are not authored:
/// every city-market supply/demand entry deterministically becomes one firm.
struct FirmNamePools: Codable, Sendable {
    let stems: [String]
    let supplierSuffixes: [String]
    let receiverSuffixes: [String]

    /// Compact built-in pool for fixture catalogs and as a decode fallback.
    static let fallback = FirmNamePools(
        stems: ["Atlas", "Nova", "Summit", "Harbor", "Cedar", "Union", "Pioneer", "Crown"],
        supplierSuffixes: ["Industries", "Works", "Supply"],
        receiverSuffixes: ["Distribution", "Market", "Trading"]
    )
}

enum FirmRole: String, Codable, Sendable {
    /// Produces the product: loads are picked up at this firm's address.
    case supplier
    /// Consumes the product: loads are delivered to this firm's address.
    case receiver
}

/// A trading company at a fixed address in one city, derived from market data.
/// Jobs start and end at firm addresses, never at an abstract "city".
struct Firm: Identifiable, Hashable, Sendable {
    let id: FirmID
    let cityID: CityID
    let productID: ProductID
    let role: FirmRole
    /// Proper noun; not localized.
    let name: String
}

/// A persistent firm→firm freight relationship — the world's standing demand.
/// Derived deterministically from city markets (never authored, never saved).
struct FreightLane: Identifiable, Hashable, Sendable {
    let id: LaneID
    let originCityID: CityID
    let destinationCityID: CityID
    let productID: ProductID
    /// Supplier firm whose address is the pickup point.
    let originFirmID: FirmID
    /// Receiver firm whose address is the delivery point.
    let destinationFirmID: FirmID
    /// Long-run average daily volume. Use `ratePerDayKg(week:worldSeed:swingPercent:)`
    /// for the fluctuated in-game value.
    let baseRatePerDayKg: Int

    /// Deterministic weekly fluctuation around the base rate. Pure function of
    /// (world seed, lane, week): no state, nothing written back to the catalog.
    func ratePerDayKg(week: Int, worldSeed: UInt64, swingPercent: Int) -> Int {
        guard swingPercent > 0 else { return baseRatePerDayKg }
        var rng = SeededRNG(seed: SeedDerivation.seed(
            // Frozen token: the string only seeds the RNG, so renaming it would
            // reshuffle every weekly swing in the world for no gain.
            worldSeed, "flow_week", .string(id.rawValue), .int(week)
        ))
        let swing = Double.random(in: -1...1, using: &rng) * Double(swingPercent) / 100
        return max(1, Int((Double(baseRatePerDayKg) * (1 + swing)).rounded()))
    }
}

/// Freight-lane balance values (content, not rules — rules live in
/// `GameCatalog.deriveLanes`).
struct LaneConfig: Codable, Sendable {
    /// Cadence of the engine's accrual tick. A rule, not balance: fine enough
    /// that docks feel continuously fed, coarse enough for the event loop.
    static let tickMinutes = 240

    /// Daily outbound freight per 100k residents (kg); sets a city's total
    /// supply throughput before concentration and floors.
    let cityOutboundKgPerDayPer100k: Int
    /// Candidate lanes below this base rate are dropped — small local traffic
    /// stays with local carriers, keeping per-city lane lists readable.
    let minimumRatePerDayKg: Int
    /// ± amplitude of the deterministic weekly rate swing, percent of base.
    let weeklySwingPercent: Int
    /// Distance falloff: destination attractiveness = demand / (1 + km/this).
    let distanceHalfWeightKm: Int
    /// How much recent production an origin dock retains, expressed as time.
    /// Caps how much can pile up: at most this window's production.
    let parcelPatienceMinutes: Int
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

/// Authored base values for one facility level. Every money and duration value
/// here is a *base*: `FacilityEconomics` scales it by the target city's own
/// catalog data, so no two cities charge the same price.
struct FacilityLevelSpec: Codable, Sendable {
    let level: Int
    let buildCost: Money
    let buildDays: Int
    let upkeepPerDay: Money
    /// Storage granted by this level. Zero outside the warehouse module.
    let storageMassKg: Int
    let storageVolumeM3: Double
    /// Vehicles that can be serviced simultaneously. Zero disables the limit.
    let docks: Int
    /// Load/unload duration multiplier in percent (100 = catalog baseline).
    let handlingPercent: Int
    /// Extra payout percent on lanes touching this city (office only).
    let lanePremiumPercent: Int
}

/// Authored ladder per module. A site is the sum of the modules installed on
/// it, so this is the whole facility content model.
struct FacilityConfig: Codable, Sendable {
    let office: [FacilityLevelSpec]
    let warehouse: [FacilityLevelSpec]
    let dock: [FacilityLevelSpec]
    /// Warehouse shelving: more tonnage in the same building.
    let racking: [FacilityLevelSpec]
    /// Dock equipment: the same trucks turned around faster.
    let forklift: [FacilityLevelSpec]

    func levels(for kind: FacilityModuleKind) -> [FacilityLevelSpec] {
        switch kind {
        case .office: office
        case .warehouse: warehouse
        case .dock: dock
        case .racking: racking
        case .forklift: forklift
        }
    }

    func spec(kind: FacilityModuleKind, level: Int) -> FacilityLevelSpec? {
        levels(for: kind).first { $0.level == level }
    }

    func maxLevel(for kind: FacilityModuleKind) -> Int {
        levels(for: kind).map(\.level).max() ?? 1
    }
}

struct EconomyConfig: Codable, Sendable {
    let startingCash: Money
    let loadingMinutes: Int
    let unloadingMinutes: Int
    /// Minimum share of a lane a parcel is billed for, however small it is.
    /// Below this, freight would buy a whole truck for pocket change.
    let fillFloor: Double
    /// How much of the empty return leg the market prices into a one-way haul
    /// (0-100). Below 100 on purpose: carriers are assumed to find *some*
    /// backhaul, so a player who actually finds one profits from the gap.
    let emptyReturnSharePercent: Int
    /// Base profit margin over a haul's true cost (0-100). This is the spot
    /// rate every lane parcel earns. Regional price level, trailer fill, local
    /// presence and competition scale this margin — never the cost recovery
    /// underneath it.
    let spotMarginPercent: Int

    // MARK: Facilities

    /// Extra payout percent on lanes that start or end in the HQ city. Small on
    /// purpose: the home-field advantage must not decide the whole network.
    let hqLanePremiumPercent: Int
    /// Authored base values per module kind and level.
    let facilities: FacilityConfig

    // MARK: Freight lanes

    /// Persistent freight-lane derivation and fluctuation tuning.
    let lanes: LaneConfig
}
