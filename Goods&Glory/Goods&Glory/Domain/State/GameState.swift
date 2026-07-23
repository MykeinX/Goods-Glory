//
//  GameState.swift
//  Goods&Glory
//
//  The complete, serializable state of one campaign. Pure value types;
//  no framework dependencies. Mutated only by SimulationEngine.
//

import Foundation

struct CompanyIdentity: Codable, Hashable, Sendable {
    var name: String
    /// Corporate accent color as "#RRGGBB". Converted to platform color in UI.
    var colorHex: String
    /// SF Symbol name used as the company emblem.
    var emblemSymbol: String
}

struct CampaignConfig: Codable, Sendable {
    let seed: UInt64
    let identity: CompanyIdentity
    let hqCity: CityID
}

struct Vehicle: Codable, Identifiable, Sendable {
    let id: VehicleID
    let typeID: VehicleTypeID
    /// Last known city. While a route leg is running this remains the departure
    /// city until arrival; map interpolation uses the route run instead.
    var cityID: CityID
    var odometerKm: Double
    /// How full this truck has been running over its recent working days. The
    /// fleet list shows this rather than the live load: a live percentage is
    /// whatever the truck happens to be doing when the screen is opened, and at
    /// speed it reads like a ticker instead of a fleet.
    var load = RollingLoadFactor()

}

/// The commercial terms of one parcel, minted when a route claims freight
/// from a persistent lane.
struct JobOffer: Codable, Identifiable, Sendable {
    let id: JobID
    let origin: CityID
    let destination: CityID
    let productID: ProductID
    let load: LoadSize
    let payout: Money
    /// Shortest road distance origin -> destination at offer creation.
    let distanceKm: Double
    /// Set when this parcel was claimed from a persistent freight lane.
    let laneID: LaneID?
    /// Pickup address: the supplying firm in the origin city (nil = city depot).
    let originFirmID: FirmID?
    /// Delivery address: the receiving firm in the destination city.
    let destinationFirmID: FirmID?
    let createdAt: GameTime
    let expiresAt: GameTime

    /// Gross revenue per kilometre of the laden leg. Two parcels with similar
    /// payouts can be very different jobs; this is the number that says so.
    var payoutPerKm: Money {
        distanceKm > 0 ? Money((Double(payout) / distanceKm).rounded()) : payout
    }
}

/// Everything one campaign is. Serialized wholesale by `SaveRepository`, and
/// the only thing `SimulationEngine` ever mutates.
struct GameState: Codable, Sendable {
    var config: CampaignConfig
    var clock: GameTime
    var cash: Money
    var vehicles: [Vehicle]
    var facilities: [Facility]
    var routes: [Route]
    /// Every accepted parcel in the network, wherever it currently sits.
    var shipments: [Shipment]
    var routeRuns: [RouteRun]
    var log: [LogEntry]
    var stats: CampaignStats
    /// Balancing instrument. Never shown in normal play; see `DebugLedger`.
    var debug: DebugLedger = DebugLedger()
    /// Freight waiting at each lane's origin dock, in kg. Accrues on the lane
    /// tick; capped by the patience window so dormant markets stay bounded.
    var laneAccrualKg: [LaneID: Int]
    /// Next lane accrual tick is processed when the clock reaches this time.
    var nextLaneTickAt: GameTime
    /// Last game-day index for which vehicle fixed costs were charged.
    var lastFixedCostDay: Int
    /// Monotonic counter backing deterministic runtime IDs.
    private(set) var nextRuntimeID: Int

    mutating func issueID() -> Int {
        defer { nextRuntimeID += 1 }
        return nextRuntimeID
    }

    static let maxLogEntries = 200
    static let minutesPerDay = 24 * 60

    /// Records one ledger line. Pure observation: it reads cash and the clock,
    /// never issues a runtime ID and never touches anything the engine reads
    /// back, so recording cannot change the simulation.
    mutating func recordDebug(_ kind: DebugEntryKind, delta: Money = 0, _ detail: String) {
        debug.append(at: clock, kind: kind, delta: delta, cash: cash, detail: detail)
    }

    mutating func appendLog(_ event: LogEvent) {
        log.append(LogEntry(id: issueID(), at: clock, event: event))
        if log.count > Self.maxLogEntries {
            log.removeFirst(log.count - Self.maxLogEntries)
        }
    }

    /// A brand-new campaign before any founding commands (vehicle purchase) run.
    /// `foundingCost` is deducted from starting cash (HQ establishment).
    static func newCampaign(
        config: CampaignConfig,
        economy: EconomyConfig,
        foundingCost: Money = 0
    ) -> GameState {
        let cash = max(0, economy.startingCash - max(0, foundingCost))
        var state = GameState(
            config: config,
            clock: .start,
            cash: cash,
            vehicles: [],
            facilities: [],
            routes: [],
            shipments: [],
            routeRuns: [],
            log: [],
            stats: CampaignStats(),
            laneAccrualKg: [:],
            nextLaneTickAt: .start,
            lastFixedCostDay: 0,
            nextRuntimeID: 1
        )
        // The founding city gets its office for free: the company needs a
        // commercial home and every physical site module builds from it.
        state.facilities.append(Facility(
            id: FacilityID(rawValue: state.issueID()),
            cityID: config.hqCity,
            isHeadquarters: true,
            foundedAt: .start,
            modules: [
                FacilityModule(
                    kind: .office,
                    level: 1,
                    operationalAt: .start,
                    upgradingTo: nil,
                    upgradeEndsAt: nil,
                    hasAnnouncedCompletion: true
                )
            ]
        ))
        state.appendLog(.companyFounded(city: config.hqCity))
        return state
    }

    func vehicle(_ id: VehicleID) -> Vehicle? {
        vehicles.first { $0.id == id }
    }

    /// The route this vehicle serves, if any. A vehicle serves at most one route.
    func route(of vehicleID: VehicleID) -> Route? {
        routes.first { $0.vehicleIDs.contains(vehicleID) }
    }

    func route(_ id: RouteID) -> Route? {
        routes.first { $0.id == id }
    }

    func routeRun(for vehicleID: VehicleID) -> RouteRun? {
        routeRuns.first { $0.vehicleID == vehicleID }
    }

    func routeRuns(of routeID: RouteID) -> [RouteRun] {
        routeRuns.filter { $0.routeID == routeID }
    }

    func shipment(_ id: JobID) -> Shipment? {
        shipments.first { $0.id == id }
    }

    /// Parcels a route has committed to carry, wherever they currently are.
    func shipments(of routeID: RouteID) -> [Shipment] {
        shipments.filter { $0.assignedRouteID == routeID }
    }

    func shipments(onBoard vehicleID: VehicleID) -> [Shipment] {
        shipments.filter { $0.location.vehicleID == vehicleID }
    }

    func shipments(storedIn facilityID: FacilityID) -> [Shipment] {
        shipments.filter { $0.location.facilityID == facilityID }
    }

    /// Cargo currently loaded on the vehicle.
    ///
    /// Sums in place rather than via `shipments(onBoard:)`, which allocated a
    /// filtered array on every call. This runs per vehicle inside the route
    /// service loop, so the allocation was the measurable part.
    func cargoLoad(of vehicleID: VehicleID) -> LoadSize {
        var massKg = 0
        var volumeM3 = 0.0
        for shipment in shipments where shipment.location.vehicleID == vehicleID {
            massKg += shipment.offer.load.massKg
            volumeM3 += shipment.offer.load.volumeM3
        }
        return LoadSize(massKg: massKg, volumeM3: volumeM3)
    }

    /// Cargo occupying a warehouse right now.
    func storedLoad(in facilityID: FacilityID) -> LoadSize {
        var massKg = 0
        var volumeM3 = 0.0
        for shipment in shipments where shipment.location.facilityID == facilityID {
            massKg += shipment.offer.load.massKg
            volumeM3 += shipment.offer.load.volumeM3
        }
        return LoadSize(massKg: massKg, volumeM3: volumeM3)
    }

    /// Warehouse contents grouped the way the player picks them: by product
    /// and final destination. Ordered by urgency, then stable key.
    func storageLots(in facilityID: FacilityID) -> [StorageLot] {
        let stored = shipments(storedIn: facilityID)
        guard !stored.isEmpty else { return [] }
        var grouped: [StorageLotKey: [Shipment]] = [:]
        for shipment in stored {
            grouped[shipment.lotKey, default: []].append(shipment)
        }
        return grouped.map { key, parcels in
            let ordered = parcels.sorted {
                ($0.offer.expiresAt, $0.id.rawValue) < ($1.offer.expiresAt, $1.id.rawValue)
            }
            return StorageLot(
                key: key,
                facilityID: facilityID,
                shipmentIDs: ordered.map(\.id),
                load: ordered.reduce(LoadSize(massKg: 0, volumeM3: 0)) { total, parcel in
                    LoadSize(
                        massKg: total.massKg + parcel.offer.load.massKg,
                        volumeM3: total.volumeM3 + parcel.offer.load.volumeM3
                    )
                },
                earliestDeadline: ordered.first?.offer.expiresAt,
                pendingPayout: ordered.reduce(0) { $0 + $1.offer.payout }
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.earliestDeadline?.totalMinutes ?? .max
            let right = rhs.earliestDeadline?.totalMinutes ?? .max
            if left != right { return left < right }
            return lhs.key.destinationCityID.rawValue < rhs.key.destinationCityID.rawValue
        }
    }

    /// The city a vehicle can be seen standing in. Nil while it is between
    /// cities: `vehicle.cityID` still holds the last one, which reads as "parked
    /// there" unless the current leg is taken into account.
    func physicalCity(of vehicle: Vehicle) -> CityID? {
        if let run = routeRun(for: vehicle.id) {
            switch run.phase {
            case .traveling: return nil
            case .servicing, .waiting: return vehicle.cityID
            }
        }
        return vehicle.cityID
    }

    /// Idle = no route run. Only idle vehicles can take new work.
    func isVehicleIdle(_ vehicleID: VehicleID) -> Bool {
        routeRun(for: vehicleID) == nil
    }

    /// Every vehicle assigned to any route, in one pass.
    ///
    /// The alternative — `route(of:)` per vehicle — is O(vehicles × routes ×
    /// vehicles-per-route), which is the worst shape in the codebase for a
    /// large fleet.
    func routedVehicleIDs() -> Set<VehicleID> {
        var ids: Set<VehicleID> = []
        for route in routes { ids.formUnion(route.vehicleIDs) }
        return ids
    }

    /// Every vehicle currently on a route run, in one pass.
    func busyVehicleIDs() -> Set<VehicleID> {
        var ids = Set<VehicleID>(minimumCapacity: routeRuns.count)
        for run in routeRuns { ids.insert(run.vehicleID) }
        return ids
    }
}
