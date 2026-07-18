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
        didSet { restartClockIfNeeded() }
    }

    private var clockTask: Task<Void, Never>?

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
        var newState = GameState.newCampaign(config: config, economy: catalog.economy)
        engine.advance(&newState, by: 0) // generate the initial offer batch

        state = newState
        phase = .playing
        speed = .normal
        persist()
        restartClockIfNeeded()
    }

    func continueGame() {
        guard let loaded = try? saveRepository.load() else { return }
        state = loaded
        phase = .playing
        speed = .paused
        restartClockIfNeeded()
    }

    func quitToMenu() {
        persist()
        stopClock()
        state = nil
        phase = .mainMenu
    }

    func abandonCampaign() {
        stopClock()
        try? saveRepository.deleteSave()
        state = nil
        phase = .mainMenu
    }

    // MARK: - Commands

    @discardableResult
    func perform(_ command: GameCommand) -> CommandError? {
        guard var current = state else { return .unknownReference }
        do {
            try engine.apply(command, to: &current)
            state = current
            persist()
            return nil
        } catch let error as CommandError {
            return error
        } catch {
            assertionFailure("unexpected engine error: \(error)")
            return .unknownReference
        }
    }

    func estimate(offer: JobOffer, vehicle: Vehicle) -> SimulationEngine.JobEstimate? {
        guard let state else { return nil }
        return engine.estimate(offer: offer, vehicle: vehicle, state: state)
    }

    // MARK: - Clock

    private func restartClockIfNeeded() {
        stopClock()
        guard phase == .playing, speed != .paused else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
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
    }

    // MARK: - Persistence

    /// Saves the current campaign. Called on commands, backgrounding and quit.
    func persist() {
        guard let state else { return }
        do {
            try saveRepository.save(state)
        } catch {
            // Persistence failure must never crash the game loop.
            print("Save failed: \(error)")
        }
    }
}
