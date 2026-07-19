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
    /// Last known city. While a job is running this remains the departure city
    /// until arrival; map interpolation uses the active job's phase instead.
    var cityID: CityID
    var assignedJobID: JobID?
    var odometerKm: Double

    var isAvailable: Bool { assignedJobID == nil }
}

enum JobUrgency: String, Codable, Sendable {
    case economy
    case normal
    case urgent
}

enum JobSource: String, Codable, Sendable {
    case spot
    case contract
}

struct JobOffer: Codable, Identifiable, Sendable {
    let id: JobID
    let origin: CityID
    let destination: CityID
    let productID: ProductID
    let load: LoadSize
    let payout: Money
    /// Shortest road distance origin -> destination at offer creation.
    let distanceKm: Double
    let urgency: JobUrgency
    let source: JobSource
    /// Set when this spot shipment was spawned by a signed contract.
    let contractID: ContractID?
    /// Pickup address: the supplying firm in the origin city (nil = city depot).
    let originFirmID: FirmID?
    /// Delivery address: the receiving firm in the destination city.
    let destinationFirmID: FirmID?
    let createdAt: GameTime
    let expiresAt: GameTime
}

enum JobPhase: String, Codable, Sendable {
    /// Driving empty to the pickup city.
    case deadheading
    case loading
    case enRoute
    case unloading
}

struct ActiveJob: Codable, Identifiable, Sendable {
    let id: JobID
    /// Snapshot of the accepted offer; offers are removed from the open list.
    let offer: JobOffer
    let vehicleID: VehicleID
    /// Roads the vehicle drives empty to reach the origin. Empty if already there.
    let deadheadRoute: [RoadTraversal]
    let deadheadKm: Double
    /// Ordered road traversals from origin to destination.
    let route: [RoadTraversal]
    /// When the vehicle started working on this job (accept time).
    let startedAt: GameTime

    var phase: JobPhase
    var phaseStartedAt: GameTime
    var phaseEndsAt: GameTime
}

/// How a contract shapes its recurring freight. The archetype decides the
/// shipment calendar and volume, not the physical work — every archetype
/// ultimately posts ordinary parcels that vehicles and routes carry.
enum ContractArchetype: String, Codable, Hashable, Sendable, CaseIterable {
    /// Steady lane: a moderate volume moves on a fixed cadence, A to B.
    case laneRecurring
    /// Periodic bulk: one large volume per cycle, far beyond a single vehicle.
    case bulkPeriodic
    /// Open-ended lane with no end date; runs until safely cancelled.
    case evergreen
    /// One source feeding several destinations by share. Forces a hub network.
    case multiDrop
}

/// One delivery endpoint of a contract. Single-destination contracts carry
/// exactly one of these; `multiDrop` carries several with shares summing to 10 000.
struct ContractDestination: Codable, Hashable, Sendable {
    let cityID: CityID
    /// Receiving firm address in that city.
    let firmID: FirmID?
    /// Share of the cycle volume in basis points. All shares sum to 10 000.
    let shareBps: Int
    let distanceKm: Double
    /// Revenue for one full `parcelMassKg` parcel delivered here. Partial
    /// parcels settle pro rata by mass.
    let payoutPerParcel: Money

    static let fullShareBps = 10_000
}

/// Fields shared by open offers and signed contracts, so pricing, UI and the
/// shipment scheduler can treat both through one interface.
protocol ContractTerms {
    var origin: CityID { get }
    var productID: ProductID { get }
    var archetype: ContractArchetype { get }
    var destinations: [ContractDestination] { get }
    var referenceVehicleTypeID: VehicleTypeID { get }
    var parcelMassKg: Int { get }
    var volumePerCycleKg: Int { get }
    var shipmentIntervalMinutes: Int { get }
    var deliveryWindowMinutes: Int { get }
    var originFirmID: FirmID? { get }
}

extension ContractTerms {
    /// Convenience view for single-destination contracts, which stay the
    /// common case across UI and tests.
    var destination: CityID { destinations.first?.cityID ?? origin }
    var destinationFirmID: FirmID? { destinations.first?.firmID }
    var distanceKm: Double { destinations.first?.distanceKm ?? 0 }
    /// Revenue for one full parcel on the primary destination.
    var payoutPerShipment: Money { destinations.first?.payoutPerParcel ?? 0 }
    /// Mass of one posted shipment. Named for the old single-parcel model.
    var shipmentMassKg: Int { parcelMassKg }
    /// Whole parcels posted per cycle across every destination.
    var parcelsPerCycle: Int {
        destinations.reduce(0) { total, destination in
            total + Self.parcelCount(
                volumeKg: cycleVolume(for: destination),
                parcelMassKg: parcelMassKg
            )
        }
    }
    /// Total revenue of one full cycle, all destinations included.
    var revenuePerCycle: Money {
        destinations.reduce(0) { total, destination in
            let volume = cycleVolume(for: destination)
            guard parcelMassKg > 0 else { return total }
            return total + Money(
                (Double(destination.payoutPerParcel) * Double(volume) / Double(parcelMassKg)).rounded()
            )
        }
    }
    var isMultiDrop: Bool { destinations.count > 1 }

    /// Mass routed to one destination in a single cycle.
    func cycleVolume(for destination: ContractDestination) -> Int {
        Int(
            (Double(volumePerCycleKg) * Double(destination.shareBps)
                / Double(ContractDestination.fullShareBps)).rounded()
        )
    }

    static func parcelCount(volumeKg: Int, parcelMassKg: Int) -> Int {
        guard parcelMassKg > 0, volumeKg > 0 else { return 0 }
        return (volumeKg + parcelMassKg - 1) / parcelMassKg
    }
}

/// Open long-term lane available for signing.
struct ContractOffer: Codable, Identifiable, Sendable, ContractTerms {
    let id: ContractID
    let origin: CityID
    let productID: ProductID
    let archetype: ContractArchetype
    let destinations: [ContractDestination]
    /// Vehicle class used to size and price each parcel.
    let referenceVehicleTypeID: VehicleTypeID
    /// Mass of one posted parcel — sized to the reference vehicle.
    let parcelMassKg: Int
    /// Total mass moved per cycle. Bulk contracts exceed one vehicle by design.
    let volumePerCycleKg: Int
    /// How often a cycle of shipments is posted after signing.
    let shipmentIntervalMinutes: Int
    /// Time a posted parcel has before it counts as late.
    let deliveryWindowMinutes: Int
    /// Preparation time between signing and the first posted cycle.
    let leadTimeMinutes: Int
    /// Contract length in game days. Nil for evergreen contracts.
    let durationDays: Int?
    /// Pickup address in the origin city.
    let originFirmID: FirmID?
    let createdAt: GameTime
    let expiresAt: GameTime
}

/// Signed contract that periodically posts shipment obligations.
/// Each shipment must be delivered before its deadline or a penalty is charged.
struct ActiveContract: Codable, Identifiable, Sendable, ContractTerms {
    let id: ContractID
    let origin: CityID
    let productID: ProductID
    let archetype: ContractArchetype
    let destinations: [ContractDestination]
    let referenceVehicleTypeID: VehicleTypeID
    let parcelMassKg: Int
    let volumePerCycleKg: Int
    let shipmentIntervalMinutes: Int
    let deliveryWindowMinutes: Int
    let signedAt: GameTime
    /// Nil for evergreen contracts: they end only when cancelled.
    let endsAt: GameTime?
    var nextShipmentAt: GameTime
    var shipmentsIssued: Int
    var shipmentsCompleted: Int
    var shipmentsMissed: Int
    /// Total compensation charged for missed shipments.
    var penaltiesPaid: Money
    /// Safe close requested: no new cycles post, committed parcels still run.
    var cancellationRequestedAt: GameTime?
    let originFirmID: FirmID?

    var isEvergreen: Bool { endsAt == nil }

    /// True once the contract must stop posting new work.
    func isClosing(at clock: GameTime) -> Bool {
        if cancellationRequestedAt != nil { return true }
        if let endsAt { return endsAt <= clock }
        return false
    }
}

// MARK: - Routes

/// What a vehicle does at a route stop. The address is derived: shipment tasks
/// use the shipment's firm address, contract tasks the contract's firm address,
/// and plain travel targets the city itself.
enum RouteTask: Codable, Hashable, Sendable {
    /// Drive here, nothing else. Allows free repositioning legs.
    case travel
    /// Load one specific accepted shipment waiting at this city.
    case pickupShipment(JobID)
    /// Unload that shipment here and collect its payout.
    case deliverShipment(JobID)
    /// Load the oldest pending shipment of this contract; waits if none is due yet.
    case pickupContract(ContractID)
    /// Unload all carried shipments of this contract here.
    case deliverContract(ContractID)
    /// Store every carried parcel that is not already at its final city into
    /// this city's warehouse. The backbone of consolidation.
    case dropToWarehouse
    /// Load parcels from this city's warehouse, earliest deadline first, until
    /// the vehicle is full. The lot narrows what may be loaded.
    case loadFromWarehouse(StorageLotKey)
    /// Unload every carried parcel whose final destination is this city and
    /// collect its payout. Makes one distribution run serve many customers.
    case deliverAll
}

/// Groups warehouse cargo the way a dispatcher thinks about it: same product,
/// same final destination, same contract. Shipments keep their own identity in
/// the engine; the lot is how the player selects and moves them in bulk.
struct StorageLotKey: Codable, Hashable, Sendable {
    let productID: ProductID
    let destinationCityID: CityID
    /// Nil for spot cargo with no contract behind it.
    let contractID: ContractID?
}

/// Where a parcel physically is right now.
enum CargoLocation: Codable, Hashable, Sendable {
    /// Waiting at its pickup address in this city.
    case address(CityID)
    /// Loaded on a vehicle.
    case vehicle(VehicleID)
    /// Stored in a warehouse, available for any route to pick up.
    case warehouse(FacilityID)

    var vehicleID: VehicleID? {
        if case .vehicle(let id) = self { return id }
        return nil
    }

    var facilityID: FacilityID? {
        if case .warehouse(let id) = self { return id }
        return nil
    }
}

struct RouteStop: Codable, Hashable, Identifiable, Sendable {
    /// Deterministic runtime id so stops stay addressable while editing.
    let id: Int
    var cityID: CityID
    var task: RouteTask
}

/// A player-built vehicle itinerary that loops until stopped. Contract routes
/// are auto-created on first vehicle assignment and remain fully editable.
struct Route: Codable, Identifiable, Sendable {
    let id: RouteID
    var name: String
    /// Non-nil when this route was auto-created for a signed contract.
    let contractID: ContractID?
    var stops: [RouteStop]
    /// Vehicles serving this route.
    var vehicleIDs: [VehicleID]
    /// Running routes spawn runs for idle assigned vehicles and loop forever.
    var isRunning: Bool
    /// Set when deletion was requested while vehicles were still executing the
    /// route. The definition remains as a tombstone until every run safely
    /// winds down, then the engine purges it automatically.
    var cancellationRequestedAt: GameTime? = nil
}

/// An accepted parcel moving through the network. It outlives any single route:
/// a parcel may be picked up by one route, stored in a warehouse, then finished
/// by another. Removed only on final delivery.
struct Shipment: Codable, Identifiable, Sendable {
    /// Same id as the originating offer.
    let id: JobID
    /// Snapshot of the accepted offer (addresses, load, payout, deadline).
    let offer: JobOffer
    var location: CargoLocation
    /// The route that committed to carrying this parcel next. Nil means the
    /// parcel is free: it sits in a warehouse or address for anyone to take.
    var assignedRouteID: RouteID?

    /// Nil while the cargo is not on a vehicle. Kept for call-site clarity.
    var loadedVehicleID: VehicleID? { location.vehicleID }

    var lotKey: StorageLotKey {
        StorageLotKey(
            productID: offer.productID,
            destinationCityID: offer.destination,
            contractID: offer.contractID
        )
    }

    /// True when this parcel can be handed over at the given city.
    func isDeliverable(at cityID: CityID) -> Bool {
        offer.destination == cityID
    }
}

/// A dispatcher-facing grouping of warehouse cargo. Derived on demand from
/// `Shipment` records; never stored, never saved.
struct StorageLot: Identifiable, Sendable {
    let key: StorageLotKey
    let facilityID: FacilityID
    /// Parcel ids ordered by deadline, then id — the order the engine loads in.
    let shipmentIDs: [JobID]
    let load: LoadSize
    let earliestDeadline: GameTime?
    /// Revenue still to be collected once these parcels reach their destination.
    let pendingPayout: Money

    var id: StorageLotKey { key }
    var parcelCount: Int { shipmentIDs.count }
}

enum RouteRunPhase: String, Codable, Sendable {
    /// Driving toward the current stop's city.
    case traveling
    /// Loading or unloading at the current stop.
    case servicing
    /// Parked at the stop (contract shipment not due yet, or idle lap guard).
    case waiting
}

/// One vehicle executing one route. Phases advance on the engine event loop.
struct RouteRun: Codable, Identifiable, Sendable {
    let id: Int
    let routeID: RouteID
    let vehicleID: VehicleID
    /// Index into the route's stops the run is heading to or working at.
    var stopIndex: Int
    var phase: RouteRunPhase
    var phaseStartedAt: GameTime
    var phaseEndsAt: GameTime
    /// City the current traveling leg started from (map interpolation).
    var legOriginCityID: CityID
    var legDistanceKm: Double
    /// When the current lap began; guards against zero-time idle loops.
    var lapStartedAt: GameTime
    /// Parcels claimed at service start, loaded at service end. A list, not a
    /// single id: one dock visit fills the vehicle rather than taking one box.
    var claimedShipmentIDs: [JobID] = []
    /// Wind-down: skip pickups, finish deliveries, then release the vehicle.
    var isWindingDown: Bool
}

enum LogEvent: Codable, Sendable {
    case companyFounded(city: CityID)
    case vehiclePurchased(typeID: VehicleTypeID, city: CityID)
    case jobAccepted(jobID: JobID, origin: CityID, destination: CityID)
    /// Loading finished; cargo is on the vehicle and travel begins.
    case jobPickedUp(jobID: JobID, origin: CityID, destination: CityID)
    case jobDelivered(jobID: JobID, destination: CityID, revenue: Money, cost: Money)
    case contractSigned(contractID: ContractID, origin: CityID, destination: CityID)
    case vehicleAssignedToRoute(vehicleID: VehicleID, routeID: RouteID)
    case vehicleUnassignedFromRoute(vehicleID: VehicleID, routeID: RouteID)
    case routeStarted(routeID: RouteID)
    case routeStopped(routeID: RouteID)
    /// A route shipment was delivered at its destination address.
    case routeShipmentDelivered(routeID: RouteID, jobID: JobID, destination: CityID, revenue: Money)
    /// A pickup was skipped (cargo missing or vehicle full); the lap continues.
    case routeShipmentSkipped(routeID: RouteID, jobID: JobID)
    /// A contract shipment passed its deadline undelivered; compensation charged.
    case contractShipmentMissed(contractID: ContractID, penalty: Money)
    case contractEnded(contractID: ContractID, completed: Int, missed: Int)
    /// Construction started. Nothing is granted until it completes.
    case facilityConstructionStarted(facilityID: FacilityID, kind: FacilityKind, city: CityID, level: Int)
    case facilityCompleted(facilityID: FacilityID, kind: FacilityKind, city: CityID, level: Int)
    case facilityDemolished(kind: FacilityKind, city: CityID)
    /// Parcels were stored in a warehouse mid-journey.
    case cargoStored(city: CityID, parcels: Int, massKg: Int)
    /// Parcels were collected from a warehouse for their onward leg.
    case cargoLoadedFromWarehouse(city: CityID, parcels: Int, massKg: Int)
    /// A drop was refused because the warehouse had no room left.
    case warehouseFull(city: CityID, refusedParcels: Int)
    /// Safe close requested on an open-ended contract.
    case contractCancellationRequested(contractID: ContractID)
    /// A contract's own dedicated route was wound down with the contract.
    case contractRouteClosed(routeID: RouteID, contractID: ContractID)
    /// A player-built route still carries tasks for a contract that has ended;
    /// those stops now do nothing and the route needs editing.
    case routeNeedsReview(routeID: RouteID, contractID: ContractID)
}

struct LogEntry: Codable, Identifiable, Sendable {
    let id: Int
    let at: GameTime
    let event: LogEvent
}

struct CampaignStats: Codable, Sendable {
    var deliveredJobs: Int = 0
    var totalRevenue: Money = 0
    var totalCost: Money = 0
}

struct GameState: Codable, Sendable {
    var config: CampaignConfig
    var clock: GameTime
    var cash: Money
    var vehicles: [Vehicle]
    var offers: [JobOffer]
    var activeJobs: [ActiveJob]
    var contractOffers: [ContractOffer]
    var activeContracts: [ActiveContract]
    var facilities: [Facility]
    var routes: [Route]
    /// Every accepted parcel in the network, wherever it currently sits.
    var shipments: [Shipment]
    var routeRuns: [RouteRun]
    var log: [LogEntry]
    var stats: CampaignStats
    /// Next spot-offer batch is generated when the clock reaches this time.
    var nextOfferBatchAt: GameTime
    /// Next open-contract batch is generated when the clock reaches this time.
    var nextContractBatchAt: GameTime
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
            offers: [],
            activeJobs: [],
            contractOffers: [],
            activeContracts: [],
            facilities: [],
            routes: [],
            shipments: [],
            routeRuns: [],
            log: [],
            stats: CampaignStats(),
            nextOfferBatchAt: .start,
            nextContractBatchAt: .start,
            lastFixedCostDay: 0,
            nextRuntimeID: 1
        )
        // The founding city gets its branch for free: the company has to have a
        // commercial home somewhere, and it is what unlocks the first contracts.
        state.facilities.append(Facility(
            id: FacilityID(rawValue: state.issueID()),
            cityID: config.hqCity,
            kind: .branch,
            level: 1,
            isHeadquarters: true,
            foundedAt: .start,
            operationalAt: .start,
            upgradingTo: nil,
            upgradeEndsAt: nil
        ))
        state.appendLog(.companyFounded(city: config.hqCity))
        return state
    }

    func vehicle(_ id: VehicleID) -> Vehicle? {
        vehicles.first { $0.id == id }
    }

    func activeJob(for vehicleID: VehicleID) -> ActiveJob? {
        activeJobs.first { $0.vehicleID == vehicleID }
    }

    /// The route this vehicle serves, if any. A vehicle serves at most one route.
    func route(of vehicleID: VehicleID) -> Route? {
        routes.first { $0.vehicleIDs.contains(vehicleID) }
    }

    /// The auto-created route of a signed contract, if a vehicle was ever assigned.
    func route(forContract contractID: ContractID) -> Route? {
        routes.first { $0.contractID == contractID }
    }

    func route(_ id: RouteID) -> Route? {
        routes.first { $0.id == id }
    }

    func activeContract(_ id: ContractID) -> ActiveContract? {
        activeContracts.first { $0.id == id }
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
    func cargoLoad(of vehicleID: VehicleID) -> LoadSize {
        shipments(onBoard: vehicleID).reduce(LoadSize(massKg: 0, volumeM3: 0)) { total, shipment in
            LoadSize(
                massKg: total.massKg + shipment.offer.load.massKg,
                volumeM3: total.volumeM3 + shipment.offer.load.volumeM3
            )
        }
    }

    /// Cargo occupying a warehouse right now.
    func storedLoad(in facilityID: FacilityID) -> LoadSize {
        shipments(storedIn: facilityID).reduce(LoadSize(massKg: 0, volumeM3: 0)) { total, shipment in
            LoadSize(
                massKg: total.massKg + shipment.offer.load.massKg,
                volumeM3: total.volumeM3 + shipment.offer.load.volumeM3
            )
        }
    }

    /// Warehouse contents grouped the way the player picks them: by product,
    /// final destination and contract. Ordered by urgency, then stable key.
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

    /// Idle = no direct job and no route run. Only idle vehicles can take new work.
    func isVehicleIdle(_ vehicleID: VehicleID) -> Bool {
        activeJob(for: vehicleID) == nil && routeRun(for: vehicleID) == nil
    }
}
