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

/// Open long-term lane available for signing.
struct ContractOffer: Codable, Identifiable, Sendable {
    let id: ContractID
    let origin: CityID
    let destination: CityID
    let productID: ProductID
    /// Vehicle class used to size and price each shipment.
    let referenceVehicleTypeID: VehicleTypeID
    /// Typical shipment mass for this lane (volume derived from product density).
    let shipmentMassKg: Int
    let distanceKm: Double
    /// Revenue paid per completed shipment.
    let payoutPerShipment: Money
    /// How often a shipment opportunity is posted after signing.
    let shipmentIntervalMinutes: Int
    /// Contracting firm addresses: pickup at origin firm, delivery at destination firm.
    let originFirmID: FirmID?
    let destinationFirmID: FirmID?
    let createdAt: GameTime
    let expiresAt: GameTime
}

/// Signed contract that periodically posts shipment obligations.
/// Each shipment must be delivered before its deadline or a penalty is charged.
struct ActiveContract: Codable, Identifiable, Sendable {
    let id: ContractID
    let origin: CityID
    let destination: CityID
    let productID: ProductID
    let referenceVehicleTypeID: VehicleTypeID
    let shipmentMassKg: Int
    let distanceKm: Double
    let payoutPerShipment: Money
    let shipmentIntervalMinutes: Int
    let signedAt: GameTime
    let endsAt: GameTime
    var nextShipmentAt: GameTime
    var shipmentsIssued: Int
    var shipmentsCompleted: Int
    var shipmentsMissed: Int
    /// Total compensation charged for missed shipments.
    var penaltiesPaid: Money
    /// Contracting firm addresses carried over from the offer.
    let originFirmID: FirmID?
    let destinationFirmID: FirmID?
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

/// An accepted market offer bound to a route, waiting at its pickup address
/// or loaded on a vehicle. Removed on delivery.
struct RouteShipment: Codable, Identifiable, Sendable {
    /// Same id as the originating offer.
    let id: JobID
    /// Snapshot of the accepted offer (addresses, load, payout).
    let offer: JobOffer
    let routeID: RouteID
    /// Nil while the cargo waits at its origin address.
    var loadedVehicleID: VehicleID?
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
    /// Contract shipment claimed at service start, applied at service end.
    var claimedShipmentID: JobID?
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
    var routes: [Route]
    var routeShipments: [RouteShipment]
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
            routes: [],
            routeShipments: [],
            routeRuns: [],
            log: [],
            stats: CampaignStats(),
            nextOfferBatchAt: .start,
            nextContractBatchAt: .start,
            lastFixedCostDay: 0,
            nextRuntimeID: 1
        )
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

    func routeShipment(_ id: JobID) -> RouteShipment? {
        routeShipments.first { $0.id == id }
    }

    func routeShipments(of routeID: RouteID) -> [RouteShipment] {
        routeShipments.filter { $0.routeID == routeID }
    }

    /// Cargo currently loaded on the vehicle across all its route shipments.
    func cargoLoad(of vehicleID: VehicleID) -> LoadSize {
        routeShipments
            .filter { $0.loadedVehicleID == vehicleID }
            .reduce(LoadSize(massKg: 0, volumeM3: 0)) { total, shipment in
                LoadSize(
                    massKg: total.massKg + shipment.offer.load.massKg,
                    volumeM3: total.volumeM3 + shipment.offer.load.volumeM3
                )
            }
    }

    /// Idle = no direct job and no route run. Only idle vehicles can take new work.
    func isVehicleIdle(_ vehicleID: VehicleID) -> Bool {
        activeJob(for: vehicleID) == nil && routeRun(for: vehicleID) == nil
    }
}
