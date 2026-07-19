//
//  GameSession.swift
//  Goods&Glory
//
//  Application layer: owns the active campaign, drives game time from real
//  time, validates player intents into engine commands, and coordinates
//  persistence. The UI observes this object and never mutates GameState.
//

import Foundation
import Observation

enum SimulationSpeed: Int, CaseIterable, Codable {
    case paused = 0
    case normal = 1
    case fast = 3
    case veryFast = 8

    /// Wall-clock interval between simulation ticks. Map vehicle motion is
    /// smoothed across this same window so sprites do not pause between jumps.
    static let clockTickSeconds: Double = 1

    /// Game minutes applied per real second (prototype pacing: 1s = 5 game min at 1x).
    var minutesPerRealSecond: Int {
        switch self {
        case .paused: 0
        case .normal: 5
        case .fast: 15
        case .veryFast: 40
        }
    }
}

enum SessionPhase {
    case mainMenu
    case founding
    case playing
}

@MainActor
@Observable
final class GameSession {
    let catalog: GameCatalog
    private let engine: SimulationEngine
    private let saveRepository: SaveRepository

    private(set) var phase: SessionPhase = .mainMenu
    private(set) var state: GameState?
    var speed: SimulationSpeed = .normal {
        didSet {
            if speed == .paused { persist() }
            restartClockIfNeeded()
        }
    }

    private var clockTask: Task<Void, Never>?
    /// Real seconds since the last autosave while the clock is running.
    private var secondsSinceAutosave = 0
    /// Kept for future energy / reliability tests. Not used while tick autosave is off.
    private static let autosaveIntervalSeconds = 30
    /// Tick-based autosave is disabled: `perform`, speed pause, background and
    /// quit already persist. Flip to `true` to re-enable interval saves in tests.
    private static let isTickAutosaveEnabled = false

    /// Transient player alerts derived from new log entries (not persisted).
    private(set) var notifications: [GameNotification] = []
    /// Highest log id already considered for toast publication.
    private var lastPublishedLogID: Int = 0
    private static let maxVisibleNotifications = 3
    private static let notificationDisplaySeconds: Double = 4.0

    init(catalog: GameCatalog, saveRepository: SaveRepository = SaveRepository()) {
        self.catalog = catalog
        self.engine = SimulationEngine(catalog: catalog)
        self.saveRepository = saveRepository
    }

    var hasSave: Bool { saveRepository.hasSave }

    // MARK: - Lifecycle

    func beginFounding() {
        phase = .founding
    }

    func cancelFounding() {
        phase = .mainMenu
    }

    /// Creates a new campaign with the chosen identity and HQ city.
    /// The company starts with cash only; vehicles are bought in-game.
    func startNewGame(identity: CompanyIdentity, hqCity: CityID) {
        let config = CampaignConfig(
            seed: UInt64.random(in: UInt64.min...UInt64.max),
            identity: identity,
            hqCity: hqCity
        )
        let foundingCost = catalog.city(hqCity).map(CityInsight.foundingCost(for:)) ?? 0
        var newState = GameState.newCampaign(
            config: config,
            economy: catalog.economy,
            foundingCost: foundingCost
        )
        engine.advance(&newState, by: 0) // generate the initial offer batch

        state = newState
        phase = .playing
        speed = .normal
        clearNotifications()
        lastPublishedLogID = 0
        publishNewLogNotifications(from: newState)
        persist()
        restartClockIfNeeded()
    }

    func continueGame() {
        guard let loaded = try? saveRepository.load() else { return }
        state = loaded
        phase = .playing
        speed = .paused
        clearNotifications()
        lastPublishedLogID = loaded.log.last?.id ?? 0
        restartClockIfNeeded()
    }

    func quitToMenu() {
        persist()
        stopClock()
        clearNotifications()
        state = nil
        phase = .mainMenu
    }

    func abandonCampaign() {
        stopClock()
        try? saveRepository.deleteSave()
        clearNotifications()
        state = nil
        phase = .mainMenu
    }

    /// App left the foreground: freeze simulation time (no catch-up on return) and save.
    func suspendForBackground() {
        stopClock()
        persist()
    }

    /// App became active again: resume at the player's current speed setting.
    func resumeFromBackground() {
        restartClockIfNeeded()
    }

    // MARK: - Commands

    @discardableResult
    func perform(_ command: GameCommand) -> CommandError? {
        guard var current = state else { return .unknownReference }
        do {
            try engine.apply(command, to: &current)
            state = current
            publishNewLogNotifications(from: current)
            persist()
            return nil
        } catch let error as CommandError {
            return error
        } catch {
            assertionFailure("unexpected engine error: \(error)")
            return .unknownReference
        }
    }

    @discardableResult
    func createRoute() -> RouteID? {
        guard perform(.createRoute(name: "")) == nil else { return nil }
        return state?.routes.last?.id
    }

    func estimate(offer: JobOffer, vehicle: Vehicle) -> SimulationEngine.JobEstimate? {
        guard let state else { return nil }
        return engine.estimate(offer: offer, vehicle: vehicle, state: state)
    }

    /// Per-shipment cycle economics of an open contract with its reference vehicle class.
    func estimate(contractOffer: ContractOffer) -> SimulationEngine.ContractEstimate? {
        guard let vehicleType = catalog.vehicleType(contractOffer.referenceVehicleTypeID) else { return nil }
        return engine.estimate(
            origin: contractOffer.origin,
            destination: contractOffer.destination,
            distanceKm: contractOffer.distanceKm,
            shipmentMassKg: contractOffer.shipmentMassKg,
            productID: contractOffer.productID,
            payoutPerShipment: contractOffer.payoutPerShipment,
            vehicleType: vehicleType
        )
    }

    /// Per-shipment cycle economics of a signed contract with a concrete vehicle.
    func estimate(contract: ActiveContract, vehicle: Vehicle) -> SimulationEngine.ContractEstimate? {
        guard let vehicleType = catalog.vehicleType(vehicle.typeID) else { return nil }
        return engine.estimate(
            origin: contract.origin,
            destination: contract.destination,
            distanceKm: contract.distanceKm,
            shipmentMassKg: contract.shipmentMassKg,
            productID: contract.productID,
            payoutPerShipment: contract.payoutPerShipment,
            vehicleType: vehicleType
        )
    }

    func estimate(route: Route, vehicle: Vehicle) -> SimulationEngine.RouteEstimate? {
        guard let state, let vehicleType = catalog.vehicleType(vehicle.typeID) else { return nil }
        return engine.estimate(route: route, vehicleType: vehicleType, state: state)
    }

    func dismissNotification(id: Int) {
        notifications.removeAll { $0.id == id }
    }

    // MARK: - Clock

    private func restartClockIfNeeded() {
        stopClock()
        guard phase == .playing, speed != .paused else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(SimulationSpeed.clockTickSeconds))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func tick() {
        guard phase == .playing, var current = state else { return }
        let minutes = speed.minutesPerRealSecond
        guard minutes > 0 else { return }
        engine.advance(&current, by: minutes)
        state = current
        publishNewLogNotifications(from: current)
        guard Self.isTickAutosaveEnabled else { return }
        secondsSinceAutosave += 1
        if secondsSinceAutosave >= Self.autosaveIntervalSeconds {
            persist()
        }
    }

    // MARK: - Notifications

    private func clearNotifications() {
        notifications = []
    }

    private func publishNewLogNotifications(from state: GameState) {
        let fresh = state.log.filter { $0.id > lastPublishedLogID }
        if let newest = state.log.last?.id {
            lastPublishedLogID = newest
        }
        for entry in fresh {
            guard let note = GameNotification.make(from: entry, catalog: catalog) else { continue }
            notifications.append(note)
            if notifications.count > Self.maxVisibleNotifications {
                notifications.removeFirst(notifications.count - Self.maxVisibleNotifications)
            }
            scheduleNotificationDismiss(id: note.id)
        }
    }

    private func scheduleNotificationDismiss(id: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.notificationDisplaySeconds))
            self?.dismissNotification(id: id)
        }
    }

    // MARK: - Persistence

    /// Saves the current campaign. Called on commands, pause, background and quit.
    /// (Tick autosave is currently disabled — see `isTickAutosaveEnabled`.)
    func persist() {
        guard let state else { return }
        do {
            try saveRepository.save(state)
            secondsSinceAutosave = 0
        } catch {
            // Persistence failure must never crash the game loop.
            print("Save failed: \(error)")
        }
    }
}
