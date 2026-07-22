//
//  VehicleRows.swift
//  Goods&Glory
//
//  The fleet list. A truck's row has to answer three things without being
//  opened — what it is, what it is doing right now, and how full it is — and
//  the previous row answered none of them: it was a name, a place and a word.
//

import SwiftUI

struct EmptyFleetCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No vehicles yet", systemImage: "truck.box")
                .font(.gg(15, .heavy))
                .foregroundStyle(Theme.brand)
            Text("Buy your first vehicle in the Shop tab to start hauling freight.")
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .surfacePanel()
    }
}

struct CompactFleetVehicleRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    var accent: Color

    private var type: VehicleTypeDefinition? { session.catalog.vehicleType(vehicle.typeID) }

    private var load: LoadSize {
        session.state?.cargoLoad(of: vehicle.id) ?? LoadSize(massKg: 0, volumeM3: 0)
    }

    private var fill: Double {
        guard let type else { return 0 }
        return load.fillRatio(in: type.capacity)
    }

    /// Where it is going and how long is left on the current leg. Nil when the
    /// truck is standing still — then the row shows the city instead.
    private var leg: (line: String, remaining: Int, progress: Double)? {
        guard let state = session.state else { return nil }
        if let run = state.routeRun(for: vehicle.id), run.phase == .traveling {
            let target = state.route(run.routeID)
                .flatMap { $0.stops.indices.contains(run.stopIndex) ? $0.stops[run.stopIndex] : nil }
            let line = "\(session.cityName(run.legOriginCityID)) → "
                + (target.map { session.cityName($0.cityID) } ?? "—")
            return (
                line,
                state.clock.minutes(until: run.phaseEndsAt),
                fraction(from: run.phaseStartedAt, to: run.phaseEndsAt, clock: state.clock)
            )
        }
        if let job = state.activeJob(for: vehicle.id) {
            let line = "\(session.cityName(job.offer.origin)) → \(session.cityName(job.offer.destination))"
            return (
                line,
                state.clock.minutes(until: job.phaseEndsAt),
                fraction(from: job.phaseStartedAt, to: job.phaseEndsAt, clock: state.clock)
            )
        }
        return nil
    }

    private func fraction(from: GameTime, to: GameTime, clock: GameTime) -> Double {
        let total = max(1, from.minutes(until: to))
        return min(1, max(0, Double(from.minutes(until: clock)) / Double(total)))
    }

    var body: some View {
        let status = VehicleStatusDisplay.describe(vehicle, state: session.state)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(status.color.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: type?.symbol ?? "truck.box.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(status.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.vehicleCode(vehicle))
                        .font(.gg(14, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(typeName)
                        .font(.gg(11, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)
                TagPill(text: status.label, color: status.color)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }

            if let leg {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(leg.line)
                            .font(.gg(11.5, .heavy))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Format.shortDuration(minutes: max(0, leg.remaining))) left")
                            .font(.gg(10.5, .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                    ThemeProgressBar(value: leg.progress, tint: status.color, height: 4)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 9, weight: .bold))
                    Text(session.cityName(vehicle.cityID))
                        .font(.gg(11.5, .heavy))
                }
                .foregroundStyle(Theme.textSecondary)
            }

            loadStrip
        }
        .padding(13)
        .surfacePanel(cornerRadius: 18)
    }

    /// How full this truck has been running lately — not what it happens to be
    /// carrying this second.
    ///
    /// The live figure was actively misleading: catch a truck the minute after
    /// it unloads and it reads 8%, and at 6× speed a fleet of live percentages
    /// reads like a stock ticker. The trailing average is the number a player
    /// can act on; what is on board right now is a footnote.
    @ViewBuilder private var loadStrip: some View {
        if let type {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(averageColor)
                    Text(average == nil
                         ? String(localized: "no full day yet")
                         : String(localized: "runs \(Int(((average ?? 0) * 100).rounded()))% full"))
                        .font(.gg(10.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    ThemeProgressBar(value: average ?? 0, tint: averageColor, height: 4)
                        .frame(maxWidth: .infinity)
                }
                Text(load.massKg > 0
                     ? String(localized: "carrying \(Format.mass(kg: load.massKg)) of \(Format.mass(kg: type.capacity.massKg)) now")
                     : String(localized: "empty right now"))
                    .font(.gg(10, .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// Trailing fill of this truck, falling back to the route it serves while
    /// the truck itself has no closed day yet.
    private var average: Double? {
        vehicle.load.current ?? session.state?.route(of: vehicle.id)?.stats.recentLoadFactor
    }

    private var averageColor: Color {
        guard let average else { return Theme.textTertiary }
        if average >= 0.7 { return Theme.mint }
        if average >= 0.35 { return accent }
        return Theme.coral
    }

    private var typeName: String {
        type.map { String(localized: String.LocalizationValue($0.name)) } ?? "Vehicle"
    }
}
