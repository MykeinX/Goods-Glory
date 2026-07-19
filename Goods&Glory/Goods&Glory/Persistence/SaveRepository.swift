//
//  SaveRepository.swift
//  Goods&Glory
//
//  Atomic JSON snapshot persistence for the active campaign.
//  Deliberately simple for the foundation phase; the interface is the
//  contract, the storage technology (SwiftData/SQLite) is a later decision.
//

import Foundation

struct SaveEnvelope: Codable {
    let saveVersion: Int
    let savedAt: Date
    let state: GameState
}

/// Headline facts about the stored campaign, shown on the main menu so the
/// player knows what "Continue" will resume before tapping it.
struct SaveSummary: Equatable, Sendable {
    let identity: CompanyIdentity
    let day: Int
    let cash: Money
    let vehicleCount: Int
    let savedAt: Date

    init(state: GameState, savedAt: Date) {
        self.identity = state.config.identity
        self.day = state.clock.day
        self.cash = state.cash
        self.vehicleCount = state.vehicles.count
        self.savedAt = savedAt
    }
}

struct SaveRepository {
    static let currentSaveVersion = 8

    private let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? URL.applicationSupportDirectory
            .appendingPathComponent("GoodsGlory", isDirectory: true)
        self.fileURL = base.appendingPathComponent("campaign.json")
    }

    var hasSave: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    func load() throws -> GameState? {
        try loadEnvelope()?.state
    }

    /// Menu-facing digest. Reads the file once at launch and after a delete —
    /// never from a SwiftUI `body`.
    func summary() -> SaveSummary? {
        guard let envelope = try? loadEnvelope() else { return nil }
        return SaveSummary(state: envelope.state, savedAt: envelope.savedAt)
    }

    private func loadEnvelope() throws -> SaveEnvelope? {
        guard hasSave else { return nil }
        let data = try Data(contentsOf: fileURL)
        // A save from an older schema cannot be read (no migration chain during
        // the prototype). Clear it rather than leaving a Continue button that
        // silently does nothing every time it is tapped.
        guard let envelope = try? JSONDecoder().decode(SaveEnvelope.self, from: data),
              envelope.saveVersion == Self.currentSaveVersion else {
            try? deleteSave()
            return nil
        }
        return envelope
    }

    func save(_ state: GameState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = SaveEnvelope(
            saveVersion: Self.currentSaveVersion,
            savedAt: Date(),
            state: state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        try data.write(to: fileURL, options: [.atomic])
    }

    func deleteSave() throws {
        guard hasSave else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
