//
//  DebugLedgerView.swift
//  Goods&Glory
//
//  A balancing instrument. Reads the engine's debug ledger, shows the money
//  breakdown that explains a losing campaign, and copies the whole thing as
//  plain text so it can be pasted into a conversation.
//
//  The summary matters more than the lines: totals answer "where is the money
//  going", the lines answer "why". Both are terse on purpose.
//

import SwiftUI
import UIKit

struct DebugLedgerView: View {
    @Environment(GameSession.self) private var session
    @State private var filter: LedgerFilter = .all
    @State private var didCopy = false

    private enum LedgerFilter: String, CaseIterable {
        case all = "All"
        case money = "Money"
        case decisions = "Decisions"

        func accepts(_ kind: DebugEntryKind) -> Bool {
            switch self {
            case .all: return true
            case .money: return kind != .decision && kind != .world
            case .decisions: return kind == .decision || kind == .world
            }
        }
    }

    private var entries: [DebugEntry] {
        (session.state?.debug.entries ?? []).filter { filter.accepts($0.kind) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryCard
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Picker("Filter", selection: $filter) {
                ForEach(LedgerFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            if entries.isEmpty {
                Text("Nothing recorded yet. Play a while, then come back.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries.reversed()) { entry in
                            line(entry)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(.top, 10)
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .navigationTitle("Balance Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(didCopy ? "Copied" : "Copy") {
                    UIPasteboard.general.string = plainText
                    didCopy = true
                }
                .font(.gg(12.5, .heavy))
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear") { session.clearDebugLedger() }
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.coral)
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let totals = LedgerTotals(entries: session.state?.debug.entries ?? [])
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Cash \(Format.money(session.state?.cash ?? 0))")
                    .font(.gg(15, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(totals.net >= 0 ? "+\(Format.money(totals.net))" : Format.money(totals.net))
                    .font(.gg(15, .heavy))
                    .foregroundStyle(totals.net >= 0 ? Theme.mint : Theme.coral)
                    .monospacedDigit()
            }
            Text("recorded window · \(totals.count) lines")
                .font(.gg(10, .bold))
                .foregroundStyle(Theme.textTertiary)

            Divider().overlay(Theme.stroke)

            totalRow("Revenue", totals.revenue, Theme.mint)
            totalRow("Running (fuel, wages)", -totals.running, Theme.textSecondary)
            totalRow("Standing (fleet, estate)", -totals.standing, Theme.warning)
            totalRow("Penalties", -totals.charges, Theme.coral)
            totalRow("Capital", -totals.capital, Theme.textTertiary)

            if totals.running > 0 || totals.standing > 0 {
                // The one ratio that explains most losing campaigns: freight
                // revenue against the cost of simply owning the operation.
                let coverage = Double(totals.revenue) / Double(max(1, totals.running + totals.standing))
                Text("revenue covers \(Int((coverage * 100).rounded()))% of operating cost")
                    .font(.gg(10.5, .heavy))
                    .foregroundStyle(coverage >= 1 ? Theme.mint : Theme.coral)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfacePanel(cornerRadius: 16)
    }

    private func totalRow(_ label: String, _ amount: Money, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.gg(11, .bold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(Format.money(amount))
                .font(.gg(11.5, .heavy))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    // MARK: Lines

    private func line(_ entry: DebugEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(stamp(entry.at))
                .foregroundStyle(Theme.textTertiary)
            Text(entry.detail)
                .foregroundStyle(color(for: entry.kind))
                .frame(maxWidth: .infinity, alignment: .leading)
            if entry.delta != 0 {
                Text(entry.delta > 0 ? "+\(entry.delta)" : "\(entry.delta)")
                    .foregroundStyle(entry.delta > 0 ? Theme.mint : Theme.coral)
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .textSelection(.enabled)
    }

    private func color(for kind: DebugEntryKind) -> Color {
        switch kind {
        case .revenue: return Theme.mint
        case .running: return Theme.textSecondary
        case .standing: return Theme.warning
        case .capital: return Theme.sky
        case .charge: return Theme.coral
        case .decision: return Theme.textPrimary
        case .world: return Theme.textTertiary
        }
    }

    /// Day + hh:mm — absolute minutes are noise when reading a session.
    private func stamp(_ time: GameTime) -> String {
        let day = time.totalMinutes / GameState.minutesPerDay + 1
        let minuteOfDay = time.totalMinutes % GameState.minutesPerDay
        return String(format: "d%02d %02d:%02d", day, minuteOfDay / 60, minuteOfDay % 60)
    }

    // MARK: Export

    /// Everything needed to reason about balance, in paste-ready plain text.
    ///
    /// The engine writes it: a diagnosis belongs next to the rules it judges,
    /// and this way a test can dump the same report a play session produces.
    private var plainText: String {
        guard let state = session.state else { return "" }
        return session.diagnosticReport(state: state)
    }
}

/// Cash movement totals over the recorded window.
private struct LedgerTotals {
    var revenue: Money = 0
    var running: Money = 0
    var standing: Money = 0
    var capital: Money = 0
    var charges: Money = 0
    var count: Int = 0

    var net: Money { revenue - running - standing - capital - charges }

    init(entries: [DebugEntry]) {
        count = entries.count
        for entry in entries {
            switch entry.kind {
            case .revenue: revenue += entry.delta
            case .running: running -= entry.delta
            case .standing: standing -= entry.delta
            case .capital: capital -= entry.delta
            case .charge: charges -= entry.delta
            case .decision, .world: break
            }
        }
    }
}
