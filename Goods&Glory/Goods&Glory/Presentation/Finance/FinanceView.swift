//
//  FinanceView.swift
//  Goods&Glory
//
//  Finance tab (design 1f): the "why am I profitable / why am I losing money"
//  screen. The hero, revenue, cost and cash figures are real campaign stats.
//  The monthly trend line, per-category expense breakdown and credit line are
//  visual shells for reporting features that have no backend yet.
//

import SwiftUI

struct FinanceView: View {
    @Environment(GameSession.self) private var session

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }
    private var revenue: Money { session.state?.stats.totalRevenue ?? 0 }
    private var cost: Money { session.state?.stats.totalCost ?? 0 }
    private var profit: Money { revenue - cost }
    private var delivered: Int { session.state?.stats.deliveredJobs ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "Finance")

                    heroCard
                    revenueCostRow
                    expenseBreakdown
                    cashCard

                    Color.clear.frame(height: Layout.tabBarClearance)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
        }
        .tint(accent)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Operating Profit")
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Format.money(profit))
                    .font(.gg(38, .heavy))
                    .foregroundStyle(profit >= 0 ? Theme.mint : Theme.coral)
                    .monospacedDigit()
                Text("\(delivered) delivered")
                    .font(.gg(12, .heavy))
                    .foregroundStyle(Theme.textSecondary)
            }
            Sparkline(trendUp: profit >= 0, tint: profit >= 0 ? Theme.mint : Theme.coral)
                .frame(height: 54)
                .padding(.top, 6)
            Text("All-time, since founding")
                .font(.gg(10.5, .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(18)
        .surfacePanel(cornerRadius: 22)
    }

    private var revenueCostRow: some View {
        HStack(spacing: 10) {
            figureCard(label: "Revenue", value: Format.money(revenue), tint: Theme.textPrimary)
            figureCard(label: "Costs", value: Format.money(cost), tint: Theme.textPrimary)
        }
    }

    private func figureCard(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            Text(value)
                .font(.gg(19, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .surfacePanel()
    }

    // Shell: proportional category split is not tracked; shown as a preview.
    private var expenseBreakdown: some View {
        let rows: [(String, Double, Color)] = [
            ("Fuel", 0.34, accent), ("Staff", 0.28, Theme.sky), ("Terminal", 0.14, Theme.violet),
            ("Maintenance", 0.11, Theme.mint), ("Insurance", 0.07, Theme.textSecondary), ("Interest", 0.06, Theme.coral)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Cost Breakdown")
                Spacer()
                Text("Preview").font(.gg(10, .heavy)).foregroundStyle(Theme.textTertiary)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.0)
                        .font(.gg(12, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 84, alignment: .leading)
                    ThemeProgressBar(value: row.1, tint: row.2, height: 9)
                    Text("\(Int(row.1 * 100))%")
                        .font(.gg(12, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .surfacePanel()
    }

    private var cashCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Cash")
                Text(Format.money(session.state?.cash ?? 0))
                    .font(.gg(16, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Theme.stroke).frame(width: 1, height: 34)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel("Credit Line")
                    Spacer()
                    Text("Preview").font(.gg(10, .heavy)).foregroundStyle(Theme.textTertiary)
                }
                ThemeProgressBar(value: 0, tint: Theme.sky, height: 7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .surfacePanel()
    }
}

/// Decorative trend line for the finance hero. Illustrative, not data-bound.
private struct Sparkline: View {
    var trendUp: Bool
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let ys: [CGFloat] = trendUp
                ? [0.85, 0.78, 0.8, 0.62, 0.66, 0.5, 0.54, 0.36, 0.4, 0.24, 0.28, 0.14, 0.08]
                : [0.2, 0.26, 0.24, 0.4, 0.36, 0.5, 0.46, 0.62, 0.58, 0.72, 0.68, 0.82, 0.9]
            let pts = ys.enumerated().map { i, y in
                CGPoint(x: w * CGFloat(i) / CGFloat(ys.count - 1), y: h * y)
            }
            ZStack {
                Path { p in
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Circle().fill(tint).frame(width: 8, height: 8)
                    .position(pts.last ?? .zero)
            }
        }
    }
}
