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

struct SaveRepository {
    static let currentSaveVersion = 7

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
        guard hasSave else { return nil }
        let data = try Data(contentsOf: fileURL)
        let envelope = try JSONDecoder().decode(SaveEnvelope.self, from: data)
        guard envelope.saveVersion == Self.currentSaveVersion else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return envelope.state
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
