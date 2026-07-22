//
//  RouteRow.swift
//  Goods&Glory
//
//  A route in the list: its name, the cities it loops, who crews it, and the
//  two numbers that say whether it is worth running — how full it runs and
//  what it clears per day, both trailing averages rather than lifetime totals.
//
//  What is deliberately *not* here: the stop-by-stop task list (that is the
//  route builder's job), a "Lane" tag (every route is a loop, so the word
//  carried no information), and the delete control — a route is expensive to
//  rebuild and must not be one stray tap away from deletion. Cancelling lives
//  in the route screen, behind the tap.
//

import SwiftUI

struct RouteRow: View {
    @Environment(GameSession.self) private var session
    let route: Route
    var accent: Color
    let onOpen: () -> Void

    /// First live contract this route covers through its pickup stops.
    private var contract: ActiveContract? {
        route.coveredContractIDs.lazy
            .compactMap { session.state?.activeContract($0) }
            .first
    }

    private var isCancelling: Bool { route.cancellationRequestedAt != nil }

    private var status: (text: String, color: Color) {
        if isCancelling { return (String(localized: "Cancelling"), Theme.warning) }
        if route.isRunning { return (String(localized: "Running"), Theme.mint) }
        return (String(localized: "Stopped"), Theme.textSecondary)
    }

    /// Cities on the loop, each named once and in lap order.
    private var loopCities: [CityID] {
        var seen: Set<CityID> = []
        return route.stops.map(\.cityID).filter { seen.insert($0).inserted }
    }

    private var loopLine: String {
        let names = loopCities.map { session.cityName($0) }
        guard names.count > 3 else { return names.joined(separator: " · ") }
        return names.prefix(3).joined(separator: " · ") + " +\(names.count - 3)"
    }

    /// Trailing fill, falling back to "did the leg carry anything" until the
    /// first day closes and the real average exists.
    private var loadFactor: Double? {
        route.stats.recentLoadFactor ?? route.stats.loadedShare
    }

    private var perDay: Money? {
        guard let clock = session.state?.clock else { return nil }
        return route.stats.profitPerDay(at: clock)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                header
                metrics
                if let hint = bottleneckHint {
                    Label(hint.text, systemImage: hint.symbol)
                        .font(.gg(11, .heavy))
                        .foregroundStyle(hint.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(14)
            .surfacePanel(cornerRadius: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(route.name)
                    .font(.gg(15, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if contract != nil {
                    TagPill(text: String(localized: "Contract"), color: Theme.brand)
                }
                Spacer(minLength: 4)
                TagPill(text: status.text, color: status.color)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.capsulepath")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                Text(loopLine)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Text("· \(loopCities.count)")
                    .font(.gg(10.5, .heavy))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    /// Crew, efficiency, earnings. Three columns, no sentences.
    private var metrics: some View {
        HStack(spacing: 0) {
            metric(
                symbol: "truck.box.fill",
                title: String(localized: "Crew"),
                value: "\(route.vehicleIDs.count)",
                tint: route.vehicleIDs.isEmpty ? Theme.coral : accent
            )
            metric(
                symbol: "gauge.with.needle",
                title: String(localized: "Loaded"),
                value: loadFactor.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                tint: loadFactor.map { $0 < 0.5 ? Theme.warning : Theme.mint } ?? Theme.textTertiary
            )
            metric(
                symbol: "banknote.fill",
                title: String(localized: "Per day"),
                value: perDay.map { Format.money($0) } ?? "—",
                tint: perDay.map { $0 < 0 ? Theme.coral : Theme.mint } ?? Theme.textTertiary
            )
        }
    }

    private func metric(symbol: String, title: String, value: String, tint: Color) -> some View {
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
                .font(.gg(16, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line naming the route's binding constraint — the answer to "what
    /// should I spend on next?". Contract trouble outranks route trouble.
    private var bottleneckHint: (text: String, symbol: String, color: Color)? {
        if contract == nil, !route.coveredContractIDs.isEmpty {
            return (
                String(localized: "Contract ended — running on spot freight"),
                "doc.badge.clock",
                Theme.warning
            )
        }
        if let contract, contract.shipmentsMissed > 0 {
            return (
                String(localized: "\(contract.shipmentsMissed) contract loads missed"),
                "exclamationmark.triangle.fill",
                Theme.coral
            )
        }
        guard let bottleneck = session.bottleneck(of: route) else { return nil }
        switch bottleneck {
        case .noVehicle:
            return (String(localized: "No vehicle — this route is idle"), "car.slash", Theme.coral)
        case .moreFreightThanCapacity(let waitingKg):
            return (
                String(localized: "\(Format.mass(kg: waitingKg)) left behind — add capacity"),
                "shippingbox.and.arrow.backward",
                Theme.warning
            )
        case .emptyReturn(let percent):
            // Framed as money left on the table, not as a defect: running one
            // way is a legitimate way to run a route.
            return (
                String(localized: "\(percent)% of the lap is unpaid — a return load would pay for it"),
                "arrow.uturn.left",
                accent
            )
        case .underloaded:
            // The Loaded column above already states the percentage; repeating
            // it as a sentence was two readings of one number. Only the advice
            // is new information.
            return (
                String(localized: "Room to spare — cover another lane on this lap"),
                "gauge.with.needle",
                Theme.textTertiary
            )
        case .healthy:
            return nil
        }
    }
}
