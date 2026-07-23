//
//  OperationsNetworkView.swift
//  Goods&Glory
//
//  The live operation as a network. One row per city the company is actually
//  working — not per vehicle, and not per city on the map. The old list grew
//  with the fleet and every card animated on every tick, so past four or five
//  trucks nothing could be followed.
//
//  Rows are ordered by tonnage and nothing else, so they keep their places
//  between ticks. Trouble is a colour and a badge, not a reshuffle.
//

import SwiftUI

struct OperationsNetworkView: View {
    @Environment(GameSession.self) private var session
    var accent: Color

    @State private var expandedCityID: CityID?

    var body: some View {
        let overview = session.operations()
        VStack(alignment: .leading, spacing: 10) {
            fleetStrip(overview)

            if overview.cities.isEmpty {
                Text("Nothing is moving yet. Start serving a freight lane from a city on the map.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surfacePanel(cornerRadius: 16)
            } else {
                SectionLabel(String(localized: "Cities \(overview.cities.count)"))
                ForEach(overview.cities) { city in
                    CityOperationsRow(
                        operations: city,
                        accent: accent,
                        isExpanded: expandedCityID == city.cityID,
                        onToggle: {
                            expandedCityID = expandedCityID == city.cityID ? nil : city.cityID
                        }
                    )
                }
            }
        }
    }

    /// Where the fleet is and what it is carrying, in one line.
    private func fleetStrip(_ overview: OperationsOverview) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                fleetPill(
                    symbol: "arrow.triangle.turn.up.right.diamond.fill",
                    count: overview.movingVehicles,
                    label: String(localized: "moving"),
                    tint: Theme.mint
                )
                fleetPill(
                    symbol: "shippingbox.fill",
                    count: overview.servicingVehicles,
                    label: String(localized: "working"),
                    tint: accent
                )
                fleetPill(
                    symbol: "truck.box",
                    count: overview.idleVehicles,
                    label: String(localized: "idle"),
                    tint: overview.idleVehicles > 0 ? Theme.warning : Theme.textTertiary
                )
            }

            HStack(spacing: 0) {
                totalColumn(
                    title: String(localized: "In transit"),
                    value: Format.mass(kg: overview.inTransitKg),
                    tint: Theme.mint
                )
                divider
                totalColumn(
                    title: String(localized: "Waiting"),
                    value: Format.mass(kg: overview.waitingKg),
                    tint: overview.waitingKg > 0 ? Theme.warning : Theme.textSecondary
                )
                divider
                totalColumn(
                    title: String(localized: "On delivery"),
                    value: Format.money(overview.payoutOnBoard),
                    tint: Theme.mint
                )
            }
            .padding(.vertical, 11)
            .surfacePanel(cornerRadius: 18)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(width: 1, height: 26)
    }

    private func totalColumn(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(.gg(9.5, .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.gg(15, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func fleetPill(symbol: String, count: Int, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
            Text("\(count)")
                .font(.gg(14, .heavy))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.gg(11, .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }
}
