//
//  PerformanceOverlay.swift
//  Goods&Glory
//
//  Developer HUD for the costs SpriteKit's own counters cannot show: how long
//  a simulation tick takes, how long the map snapshot takes to build, and how
//  much state those numbers are being paid for.
//
//  It polls on a timer instead of observing anything, so watching the numbers
//  cannot itself cause SwiftUI updates — a HUD that invalidates the view every
//  frame would measure its own overhead.
//

import SwiftUI

struct PerformanceOverlay: View {
    let state: GameState

    /// Budget for one simulation tick. Ticks fire once per real second, so
    /// anything approaching a frame's worth of work is already a warning.
    private static let tickBudgetMilliseconds: Double = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let monitor = PerformanceMonitor.shared
            VStack(alignment: .leading, spacing: 3) {
                row(
                    "tick",
                    value: String(format: "%.2f ms", monitor.tickMilliseconds),
                    peak: String(format: "%.2f", monitor.peakTickMilliseconds),
                    isHot: monitor.tickMilliseconds > Self.tickBudgetMilliseconds
                )
                row(
                    "snap",
                    value: String(format: "%.2f ms", monitor.snapshotMilliseconds),
                    peak: String(format: "%.2f", monitor.peakSnapshotMilliseconds),
                    isHot: monitor.snapshotMilliseconds > Self.tickBudgetMilliseconds
                )
                row(
                    "save",
                    value: String(format: "%.2f ms", monitor.saveMilliseconds),
                    peak: nil,
                    isHot: monitor.saveMilliseconds > 8
                )
                Divider().overlay(Theme.stroke)
                Text(counts)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.62)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var counts: String {
        "veh \(state.vehicles.count)  job \(state.activeJobs.count)  run \(state.routeRuns.count)\n"
            + "off \(state.offers.count)  shp \(state.shipments.count)  fac \(state.facilities.count)"
    }

    private func row(_ label: String, value: String, peak: String?, isHot: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 30, alignment: .leading)
            Text(value)
                .foregroundStyle(isHot ? Theme.coral : Theme.mint)
            if let peak {
                Text("↑\(peak)")
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .font(.system(size: 10, weight: .bold, design: .monospaced))
    }
}
