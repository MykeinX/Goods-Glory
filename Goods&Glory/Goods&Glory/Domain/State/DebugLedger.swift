//
//  DebugLedger.swift
//  Goods&Glory
//
//  A balancing instrument, not a player feature.
//
//  Every line records one money movement together with the unit economics
//  behind it — what was carried, how far, how full, and what it cost per km.
//  That is the whole point: "the lane loses money" is not actionable, but
//  "$1.86/km revenue against $2.40/km cost at 38% fill" is. Lines are terse on
//  purpose so a long session can be read end to end without scrolling past the
//  part that matters.
//
//  Written only by SimulationEngine, always deterministically, so it cannot
//  break the determinism contract.
//

import Foundation

/// What a ledger line is about. Kept coarse: the detail lives in the text, the
/// kind exists for filtering and colour.
enum DebugEntryKind: String, Codable, Sendable {
    /// Money in from delivering freight.
    case revenue
    /// Money out for running a vehicle (fuel, wear, wages).
    case running
    /// Money out that accrues whether or not anything moves.
    case standing
    /// Capital spend: vehicles, facilities.
    case capital
    /// Penalties and other charges.
    case charge
    /// A decision the player made.
    case decision
    /// World state worth knowing when reading the numbers.
    case world
}

struct DebugEntry: Codable, Identifiable, Sendable {
    let id: Int
    let at: GameTime
    let kind: DebugEntryKind
    /// Cash delta in whole dollars; zero for non-money lines.
    let delta: Money
    /// Cash after this movement.
    let cash: Money
    /// Pre-formatted, compact. Written in the engine because the whole value of
    /// this log is density, and only the engine knows the numbers in context.
    let detail: String
}

/// Bounded, append-only debug record.
struct DebugLedger: Codable, Sendable {
    /// Enough for a long balancing session, small enough to keep saves sane.
    static let capacity = 1_500

    var entries: [DebugEntry] = []
    /// Set false to stop recording (kept in state so it survives a reload).
    var isRecording: Bool = true
    /// Line numbering lives here rather than on `GameState.issueID()`: runtime
    /// IDs are part of the determinism contract, and observing the simulation
    /// must never move them. Toggling recording cannot change what the engine
    /// computes.
    private var nextLineNumber: Int = 1

    mutating func append(at clock: GameTime, kind: DebugEntryKind, delta: Money, cash: Money, detail: String) {
        guard isRecording else { return }
        entries.append(DebugEntry(
            id: nextLineNumber,
            at: clock,
            kind: kind,
            delta: delta,
            cash: cash,
            detail: detail
        ))
        nextLineNumber += 1
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    mutating func clear() {
        entries.removeAll()
    }
}
