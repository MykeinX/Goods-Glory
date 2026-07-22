//
//  RollingLoadFactor.swift
//  Goods&Glory
//
//  How full something ran, averaged over the last few working days.
//
//  A live fill reading is almost never the answer to a player's question. Catch
//  a truck the minute after it unloads and it reads 8%; catch it on the laden
//  leg and it reads 100%. Neither says whether the lane is worth running, and
//  at 6× speed a screen of live percentages turns into a ticker.
//
//  Measured in *minutes worked* rather than kilometres driven, because a
//  vehicle shuttling a dock into a warehouse across town covers no distance and
//  a kilometre-based average would report nothing at all for it. Standing on a
//  dock is as much of the day as driving.
//
//  Shared by routes and vehicles: the same window, the same definition, one
//  copy of the midnight bookkeeping.
//

import Foundation

struct RollingLoadFactor: Codable, Hashable, Sendable {
    /// How many completed working days the average covers.
    static let dayCount = 3

    /// Minutes worked in the open day, and those minutes weighted by fill.
    private var dayMinutes: Double = 0
    private var dayPayloadMinutes: Double = 0
    /// Closed days' factors, oldest first. Idle days are never recorded — a
    /// parked vehicle has no efficiency, and averaging in zeros would make a
    /// good lane look bad for standing still.
    private var recent: [Double] = []
    private var dayIndex: Int?

    /// The synthesized memberwise initialiser is private here (the storage is),
    /// so an empty record needs its own way in.
    init() {}

    /// Nil until the first working day closes.
    var average: Double? {
        guard !recent.isEmpty else { return nil }
        return recent.reduce(0, +) / Double(recent.count)
    }

    /// The open day so far, for callers that would rather show something than
    /// nothing on day one.
    var today: Double? {
        guard dayMinutes > 0 else { return nil }
        return min(1, max(0, dayPayloadMinutes / dayMinutes))
    }

    /// Best available reading: the settled average, falling back to today.
    var current: Double? { average ?? today }

    /// Records a stretch of work — a driven leg or a spell on a dock.
    mutating func note(minutes: Int, fill: Double, at clock: GameTime) {
        guard minutes > 0 else { return }
        roll(to: clock)
        dayMinutes += Double(minutes)
        dayPayloadMinutes += Double(minutes) * min(1, max(0, fill))
    }

    /// Closes any days that have passed. Safe to call at any time.
    mutating func roll(to clock: GameTime) {
        let today = clock.totalMinutes / GameState.minutesPerDay
        guard let open = dayIndex else {
            dayIndex = today
            return
        }
        guard open < today else { return }
        if dayMinutes > 0 {
            recent.append(min(1, max(0, dayPayloadMinutes / dayMinutes)))
            if recent.count > Self.dayCount {
                recent.removeFirst(recent.count - Self.dayCount)
            }
        }
        dayMinutes = 0
        dayPayloadMinutes = 0
        dayIndex = today
    }
}
