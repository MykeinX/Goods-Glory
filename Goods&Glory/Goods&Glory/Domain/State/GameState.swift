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

struct JobOffer: Codable, Identifiable, Sendable {
    let id: JobID
    let origin: CityID
    let destination: CityID
    let productID: ProductID
    let load: LoadSize
    let payout: Money
    /// Shortest road distance origin -> destination at offer creation.
    let distanceKm: Double
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

enum LogEvent: Codable, Sendable {
    case companyFounded(city: CityID)
    case vehiclePurchased(typeID: VehicleTypeID, city: CityID)
    case jobAccepted(jobID: JobID, origin: CityID, destination: CityID)
    case jobDelivered(jobID: JobID, destination: CityID, revenue: Money, cost: Money)
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
    var log: [LogEntry]
    var stats: CampaignStats
    /// Next spot-offer batch is generated when the clock reaches this time.
    var nextOfferBatchAt: GameTime
    /// Monotonic counter backing deterministic runtime IDs.
    private(set) var nextRuntimeID: Int

    mutating func issueID() -> Int {
        defer { nextRuntimeID += 1 }
        return nextRuntimeID
    }

    static let maxLogEntries = 200

    mutating func appendLog(_ event: LogEvent) {
        log.append(LogEntry(id: issueID(), at: clock, event: event))
        if log.count > Self.maxLogEntries {
            log.removeFirst(log.count - Self.maxLogEntries)
        }
    }

    /// A brand-new campaign before any founding commands (vehicle purchase) run.
    static func newCampaign(config: CampaignConfig, economy: EconomyConfig) -> GameState {
        var state = GameState(
            config: config,
            clock: .start,
            cash: economy.startingCash,
            vehicles: [],
            offers: [],
            activeJobs: [],
            log: [],
            stats: CampaignStats(),
            nextOfferBatchAt: .start,
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
}
