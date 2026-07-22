//
//  CityOperationsRow.swift
//  Goods&Glory
//
//  One city in the operations network: what is stuck here, what is heading
//  here, and who is working it. The collapsed row is meant to be read in a
//  glance across a list; the expanded one answers "which parcels exactly".
//

import SwiftUI

struct CityOperationsRow: View {
    @Environment(GameSession.self) private var session
    let operations: CityOperations
    var accent: Color
    var isExpanded: Bool
    var onToggle: () -> Void

    private var statusTint: Color {
        if operations.isStalled { return Theme.coral }
        if operations.isUrgent { return Theme.warning }
        return Theme.mint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                summary
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Theme.stroke)
                CityOperationsDetailPanel(cityID: operations.cityID, accent: accent)
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    operations.isStalled ? Theme.coral.opacity(0.55) : Theme.stroke,
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.18), value: isExpanded)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 8, height: 8)
                Text(session.cityName(operations.cityID))
                    .font(.gg(15, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if operations.isStalled {
                    TagPill(text: String(localized: "No truck"), color: Theme.coral)
                } else if operations.isUrgent {
                    TagPill(text: String(localized: "Time short"), color: Theme.warning)
                }
                Spacer(minLength: 4)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Theme.textTertiary)
            }

            // The three numbers the row exists for: out, in, who is on it.
            HStack(spacing: 0) {
                directionColumn(
                    symbol: "arrow.up.forward",
                    title: String(localized: "Out"),
                    value: Format.mass(kg: operations.waitingKg),
                    caption: operations.waitingParcels > 0
                        ? String(localized: "\(operations.waitingParcels) waiting")
                        : String(localized: "clear"),
                    tint: operations.waitingKg > 0 ? statusTint : Theme.textTertiary
                )
                directionColumn(
                    symbol: "arrow.down.forward",
                    title: String(localized: "In"),
                    value: Format.mass(kg: operations.inboundKg),
                    caption: operations.nextArrivalMinutes.map {
                        String(localized: "\(Format.shortDuration(minutes: $0)) to first")
                    } ?? String(localized: "none coming"),
                    tint: operations.inboundKg > 0 ? Theme.mint : Theme.textTertiary
                )
                // Routes, not trucks, as the headline: a truck stands on a dock
                // for minutes, so a live count blinked between 0 and 2 while
                // the city was in fact perfectly well served.
                directionColumn(
                    symbol: "arrow.triangle.capsulepath",
                    title: String(localized: "Served by"),
                    value: "\(operations.routesServing)",
                    caption: operations.vehiclesHere > 0
                        ? String(localized: "\(operations.vehiclesHere) truck(s) here now")
                        : (operations.vehiclesInbound > 0
                           ? String(localized: "\(operations.vehiclesInbound) on the way")
                           : String(localized: "route(s) calling")),
                    tint: operations.routesServing > 0 ? accent : Theme.textTertiary
                )
            }

            if operations.storedKg > 0 || operations.dockKg > 0 {
                HStack(spacing: 10) {
                    if operations.storedKg > 0 {
                        footnote(
                            symbol: "archivebox.fill",
                            text: String(localized: "\(Format.mass(kg: operations.storedKg)) in warehouse"),
                            tint: Theme.sky
                        )
                    }
                    if operations.dockKg > 0 {
                        // Freight the city is producing that nobody has claimed.
                        footnote(
                            symbol: "tray.full.fill",
                            text: String(localized: "\(Format.mass(kg: operations.dockKg)) on the dock"),
                            tint: Theme.warning
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func footnote(symbol: String, text: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.gg(10.5, .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }

    private func directionColumn(
        symbol: String,
        title: String,
        value: String,
        caption: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .heavy))
                Text(title.uppercased())
                    .font(.gg(9.5, .heavy))
                    .tracking(0.5)
            }
            .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.gg(15, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.gg(10, .bold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The expanded half of a city row.
struct CityOperationsDetailPanel: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID
    var accent: Color

    var body: some View {
        let detail = session.operationsDetail(for: cityID)
        VStack(alignment: .leading, spacing: 9) {
            if !detail.waiting.isEmpty {
                label(String(localized: "Waiting to leave"))
                ForEach(detail.waiting) { movement in
                    movementLine(movement, symbol: "arrow.up.forward", prefix: "→")
                }
            }
            if !detail.inbound.isEmpty {
                label(String(localized: "On the way here"))
                ForEach(detail.inbound) { movement in
                    movementLine(movement, symbol: "arrow.down.forward", prefix: "←")
                }
            }
            if detail.vehicleIDs.isEmpty {
                Text("No truck standing here.")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                label(String(localized: "Trucks here"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(detail.vehicleIDs, id: \.self) { vehicleID in
                            vehicleChip(vehicleID)
                        }
                    }
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.gg(9.5, .heavy))
            .tracking(0.6)
            .foregroundStyle(Theme.textTertiary)
    }

    private func movementLine(
        _ movement: CityOperationsDetail.Movement,
        symbol: String,
        prefix: String
    ) -> some View {
        let late = movement.minutesToDeadline == 0
        return HStack(spacing: 8) {
            Image(systemName: session.productSymbol(movement.productID))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 18)
            Text("\(prefix) \(session.cityName(movement.counterpartCityID))")
                .font(.gg(12, .heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(Format.mass(kg: movement.massKg))
                .font(.gg(11, .bold))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            Text(late
                 ? String(localized: "late")
                 : Format.shortDuration(minutes: movement.minutesToDeadline))
                .font(.gg(11, .heavy))
                .foregroundStyle(late ? Theme.coral : Theme.textTertiary)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
    }

    private func vehicleChip(_ vehicleID: VehicleID) -> some View {
        let vehicle = session.state?.vehicle(vehicleID)
        let status = vehicle.map { VehicleStatusDisplay.describe($0, state: session.state) }
        return HStack(spacing: 5) {
            Circle()
                .fill(status?.color ?? Theme.textTertiary)
                .frame(width: 6, height: 6)
            Text(vehicle.map { session.vehicleCode($0) } ?? "—")
                .font(.gg(11, .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(status?.label ?? "")
                .font(.gg(10, .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.backgroundTop.opacity(0.6)))
        .overlay(Capsule().stroke(Theme.strokeSoft, lineWidth: 1))
    }
}
