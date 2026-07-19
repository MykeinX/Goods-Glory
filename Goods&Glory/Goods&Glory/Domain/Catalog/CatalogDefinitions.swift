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
    /// Static urban traffic proxy. 1000 means free-flow travel time; runtime
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

/// Spot urgency band: payout multiplier, offer lifetime and selection weight.
struct UrgencyTier: Codable, Hashable, Sendable {
    let id: String
    let multiplier: Double
    let lifetimeMinutes: Int
    let weight: Int
}

/// Authored base values for one facility level. Every money and duration value
/// here is a *base*: `FacilityEconomics` scales it by the target city's own
/// catalog data, so no two cities charge the same price.
struct FacilityLevelSpec: Codable, Sendable {
    let level: Int
    let buildCost: Money
    let buildDays: Int
    let upkeepPerDay: Money
    /// Warehouse storage. Zero for branches — a branch stores no cargo.
    let storageMassKg: Int
    let storageVolumeM3: Double
    /// Vehicles that can be serviced simultaneously. Zero disables the limit.
    let docks: Int
    /// Load/unload duration multiplier in percent (100 = catalog baseline).
    let handlingPercent: Int
    /// Contract offer slot multiplier in percent (branch only).
    let contractSlotPercent: Int
    /// Extra payout percent on lanes touching this city (branch only).
    let lanePremiumPercent: Int
}

struct FacilityConfig: Codable, Sendable {
    let branch: [FacilityLevelSpec]
    let warehouse: [FacilityLevelSpec]

    func levels(for kind: FacilityKind) -> [FacilityLevelSpec] {
        switch kind {
        case .branch: branch
        case .warehouse: warehouse
        }
    }

    func spec(kind: FacilityKind, level: Int) -> FacilityLevelSpec? {
        levels(for: kind).first { $0.level == level }
    }

    func maxLevel(for kind: FacilityKind) -> Int {
        levels(for: kind).map(\.level).max() ?? 1
    }
}

struct EconomyConfig: Codable, Sendable {
    let startingCash: Money
    let loadingMinutes: Int
    let unloadingMinutes: Int
    /// A new batch of spot job offers is generated every interval.
    let offerGenerationIntervalMinutes: Int
    /// Fallback lifetime when a tier is unavailable (normally unused).
    let offerLifetimeMinutes: Int
    /// Percent chance (0-100) for each additional slot after the guaranteed local offer.
    let offerChancePercent: Int
    /// Hard cap on simultaneous open spot offers per origin city.
    let maxOpenOffersPerCity: Int
    /// Residents per additional offer slot: a city gets
    /// min(maxOpenOffersPerCity, 1 + population / offerSlotPopulation) slots.
    let offerSlotPopulation: Int
    /// Lower bound of the fill factor: fillFloor + (1 - fillFloor) * util.
    let fillFloor: Double
    /// Base profit margin over a haul's true cost (0-100). Urgency, regional
    /// price level, trailer fill and local presence scale this margin — never
    /// the cost recovery underneath it.
    let spotMarginPercent: Int
    /// Spot urgency bands (economy / normal / urgent). Weights need not sum to 100.
    let urgencyTiers: [UrgencyTier]
    /// How often new open contract offers are generated.
    let contractOfferIntervalMinutes: Int
    let maxOpenContractOffers: Int
    /// Signed contract length in game days.
    let contractDurationDays: Int
    /// Profit margin over the reference round-trip cost priced into each
    /// contract shipment (0-100). Contract lanes include the empty return leg.
    let contractMarginPercent: Int
    /// Compensation charged when a shipment misses its deadline, as a percent
    /// of that shipment's payout (0-100).
    let contractPenaltyPercent: Int

    // MARK: Facilities

    /// Extra payout percent on lanes that start or end in the HQ city. Small on
    /// purpose: the home-field advantage must not decide the whole network.
    let hqLanePremiumPercent: Int
    /// Authored base values per facility kind and level.
    let facilities: FacilityConfig

    // MARK: Contract shaping

    /// Delivery window granted to a posted shipment, as a percent of the
    /// reference one-way cycle. 100 = exactly one loaded run, no slack.
    let contractDeliveryWindowPercent: Int
    /// Lower bound of the delivery window as a percent of the shipment interval,
    /// so daily lanes still leave a workable margin.
    let contractDeliveryWindowFloorPercent: Int
    /// Preparation time granted between signing and the first posted shipment,
    /// as a percent of one reference cycle. Gives the player time to position.
    let contractLeadTimePercent: Int
    /// Deliveries the company must complete before shippers offer recurring
    /// lanes. The opening hours are spot work; contracts are earned.
    let contractsUnlockAfterDeliveries: Int
}
