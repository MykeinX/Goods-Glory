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
import QuartzCore

enum SimulationSpeed: Int, CaseIterable, Codable {
    case paused = 0
    case normal = 1
    case fast = 3
    case veryFast = 6

    /// Wall-clock interval between simulation ticks. Map vehicle motion is
    /// smoothed across this same window so sprites do not pause between jumps.
    static let clockTickSeconds: Double = 1

    /// Game minutes applied per real second (1× = 10 min, 3× = 30 min, 6× = 60 min).
    var minutesPerRealSecond: Int {
        switch self {
        case .paused: 0
        case .normal: 10
        case .fast: 30
        case .veryFast: 60
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

    /// Digest of the stored campaign, or nil when there is none. Cached and
    /// observable: the main menu must never stat the filesystem from `body`.
    private(set) var saveSummary: SaveSummary?

    private let saveWriter: SaveWriter
    /// Debounce timer for background saves. Cancelled and replaced by each new
    /// persist request so a burst of commands costs one write, not five.
    private var pendingSaveTask: Task<Void, Never>?
    private static let saveDebounce = Duration.milliseconds(400)

    init(catalog: GameCatalog, saveRepository: SaveRepository = SaveRepository()) {
        self.catalog = catalog
        self.engine = SimulationEngine(catalog: catalog)
        self.saveRepository = saveRepository
        self.saveWriter = SaveWriter(repository: saveRepository)
        self.saveSummary = saveRepository.summary()
    }

    var hasSave: Bool { saveSummary != nil }

    /// Drops the stored campaign without touching the current phase. Used by
    /// the main menu's Settings screen.
    func deleteSave() {
        // Kill the debounce first, then delete through the writer actor so a
        // write that is already in flight cannot land after the delete.
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        saveSummary = nil
        Task { [saveWriter] in await saveWriter.delete() }
    }

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
        speed = AppSettings.shared.resumesPaused ? .paused : .normal
        clearNotifications()
        lastPublishedLogID = loaded.log.last?.id ?? 0
        restartClockIfNeeded()
    }

    func quitToMenu() {
        persistImmediately()
        stopClock()
        clearNotifications()
        state = nil
        phase = .mainMenu
    }

    func abandonCampaign() {
        stopClock()
        deleteSave()
        clearNotifications()
        state = nil
        phase = .mainMenu
    }

    /// App left the foreground: freeze simulation time (no catch-up on return) and save.
    func suspendForBackground() {
        stopClock()
        persistImmediately()
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

    func estimate(route: Route, vehicle: Vehicle) -> SimulationEngine.RouteEstimate? {
        guard let state, let vehicleType = catalog.vehicleType(vehicle.typeID) else { return nil }
        return engine.estimate(route: route, vehicleType: vehicleType, state: state)
    }

    // MARK: - Facilities (read-only views for the UI)

    /// Price, build time and capacity of a facility in a specific city.
    func upgradeQuote(for module: FacilityModule, in cityID: CityID) -> FacilityQuote? {
        engine.upgradeQuote(for: module, in: cityID)
    }

    func quote(kind: FacilityModuleKind, level: Int = 1, city cityID: CityID) -> FacilityQuote? {
        engine.quote(kind: kind, level: level, city: cityID)
    }


    /// Remaining room in a warehouse, for the city and facility screens.
    func freeStorage(of facility: Facility) -> LoadSize? {
        guard let state, facility.operationalModule(.warehouse, at: state.clock) != nil else { return nil }
        return engine.freeStorage(of: facility, state: state)
    }

    /// Total storage a site offers, warehouse plus racking.
    func storageCapacity(of facility: Facility) -> LoadSize {
        guard let state else { return LoadSize(massKg: 0, volumeM3: 0) }
        return engine.storageCapacity(of: facility, state: state)
    }

    /// Balancing instrument: wipes the recorded window so the next session
    /// reads clean. Never touches simulation state.
    func clearDebugLedger() {
        state?.debug.clear()
        persist()
    }

    /// The campaign written out for diagnosis — the artefact a play session
    /// hands over when something looks wrong.
    func diagnosticReport(state: GameState) -> String {
        engine.diagnosticReport(state: state)
    }

    /// The whole operation as a per-city network, for the operations tab.
    func operations() -> OperationsOverview {
        guard let state else { return .empty }
        return OperationsOverview.make(state: state, catalog: catalog)
    }

    /// What exactly is waiting, arriving and parked in one city.
    func operationsDetail(for cityID: CityID) -> CityOperationsDetail {
        guard let state else { return .empty }
        return CityOperationsDetail.make(cityID: cityID, state: state)
    }

    /// The one constraint holding a lane back, for the lane dashboard.
    func bottleneck(of route: Route) -> SimulationEngine.RouteBottleneck? {
        guard let state else { return nil }
        return engine.bottleneck(of: route, state: state)
    }

    /// Total daily upkeep of every standing facility.
    func facilityUpkeepPerDay() -> Money {
        guard let state else { return 0 }
        return engine.facilityUpkeepPerDay(state: state)
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
        let startedAt = CACurrentMediaTime()
        engine.advance(&current, by: minutes)
        PerformanceMonitor.shared.recordTick(CACurrentMediaTime() - startedAt)
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
        guard AppSettings.shared.showsGameplayToasts else { return }
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

    /// Queues a save of the current campaign. Called on every command, so the
    /// disk write is debounced and performed off the main thread — a player
    /// tapping "accept job" should never wait on JSON encoding.
    ///
    /// The observable `saveSummary` is updated immediately from memory, so the
    /// UI never has to wait for the write to know what is stored.
    func persist() {
        guard let state else { return }
        saveSummary = SaveSummary(state: state, savedAt: Date())
        secondsSinceAutosave = 0

        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [saveWriter] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            await saveWriter.write(state)
        }
    }

    /// Writes the campaign right now, on the calling thread, and returns only
    /// once it is on disk. Used where losing the last few hundred milliseconds
    /// is unacceptable: leaving the app and quitting to the menu. Blocking the
    /// main thread is the correct trade here — the player is already leaving.
    func persistImmediately() {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        guard let state else { return }
        do {
            let startedAt = CACurrentMediaTime()
            try saveRepository.save(state)
            PerformanceMonitor.shared.recordSave(CACurrentMediaTime() - startedAt)
            saveSummary = SaveSummary(state: state, savedAt: Date())
            secondsSinceAutosave = 0
        } catch {
            // Persistence failure must never crash the game loop.
            print("Save failed: \(error)")
        }
    }
}
