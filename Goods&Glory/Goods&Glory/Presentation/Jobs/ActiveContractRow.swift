//
//  ActiveContractRow.swift
//  Goods&Glory
//
//  A signed contract in the portfolio: coverage, cadence and crewing.
//

import SwiftUI

struct ActiveContractRow: View {
    @Environment(GameSession.self) private var session
    let contract: ActiveContract
    var accent: Color
    @State private var showsAssignSheet = false
    @State private var assignError: CommandError?

    private var route: Route? { session.state?.route(serving: contract.id) }

    private var assignedVehicles: [Vehicle] {
        guard let route, let state = session.state else { return [] }
        return route.vehicleIDs.compactMap { state.vehicle($0) }
    }

    /// Shipments posted and still waiting for a vehicle.
    private var pendingShipments: Int {
        (session.state?.offers ?? []).count { $0.source == .contract && $0.contractID == contract.id }
    }

    private var laneTitle: String {
        let origin = session.cityName(contract.origin)
        let drops = contract.destinations.map { session.cityName($0.cityID) }
        guard drops.count > 1 else { return "\(origin) → \(drops.first ?? "—")" }
        return "\(origin) → \(drops[0]) +\(drops.count - 1)"
    }

    private var archetypeLabel: String { ContractArchetypeDisplay.label(contract.archetype) }

    private var archetypeColor: Color { ContractArchetypeDisplay.color(contract.archetype) }

    /// One honest line about whether this contract's freight is moving.
    @ViewBuilder private var coverageBanner: some View {
        if let coverage = session.coverage(of: contract) {
            let style = coverageStyle(coverage)
            HStack(spacing: 6) {
                Image(systemName: style.symbol)
                    .font(.caption)
                    .foregroundStyle(style.color)
                Text(style.text)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(style.color)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.color.opacity(0.10))
            )
        }
    }

    private func coverageStyle(
        _ coverage: SimulationEngine.ContractCoverage
    ) -> (symbol: String, color: Color, text: String) {
        switch coverage {
        case .notStarted(let minutes):
            return (
                "clock.fill",
                Theme.sky,
                String(localized: "Preparation time — first load in \(Format.duration(minutes: minutes)).")
            )
        case .covered:
            return (
                "checkmark.circle.fill",
                Theme.mint,
                String(localized: "All posted freight is moving.")
            )
        case .partial(let moving, let waiting):
            return (
                "exclamationmark.circle.fill",
                accent,
                String(localized: "\(moving) parcel(s) moving, \(waiting) still unclaimed.")
            )
        case .uncovered(let waiting):
            return (
                "exclamationmark.triangle.fill",
                Theme.coral,
                String(localized: "\(waiting) parcel(s) waiting with nothing carrying them.")
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(laneTitle)
                    .font(.gg(14.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                TagPill(text: archetypeLabel, color: archetypeColor)
            }
            // Status at a glance: next load, remaining term, delivery record.
            HStack(spacing: 7) {
                if let clock = session.state?.clock {
                    StatChip(
                        symbol: "clock.fill",
                        text: Format.shortDuration(
                            minutes: max(0, clock.minutes(until: contract.nextShipmentAt))
                        ),
                        tint: Theme.sky
                    )
                    StatChip(
                        symbol: contract.isEvergreen ? "infinity" : "calendar",
                        text: contract.endsAt.map {
                            Format.shortDuration(minutes: max(0, clock.minutes(until: $0)))
                        } ?? "∞",
                        tint: Theme.textSecondary
                    )
                }
                StatChip(
                    symbol: "checkmark.circle.fill",
                    text: "\(contract.shipmentsCompleted)",
                    tint: Theme.mint
                )
                if contract.shipmentsMissed > 0 {
                    StatChip(
                        symbol: "exclamationmark.triangle.fill",
                        text: "\(contract.shipmentsMissed)",
                        tint: Theme.coral
                    )
                }
                Spacer(minLength: 0)
            }

            // Coverage measures whether freight is actually moving, not whether
            // a vehicle happens to sit on the contract's own auto-route.
            coverageBanner

            if !assignedVehicles.isEmpty {
                ForEach(assignedVehicles) { vehicle in
                    HStack(spacing: 8) {
                        if let type = session.catalog.vehicleType(vehicle.typeID) {
                            Label(
                                Format.vehicleCode(typeName: type.name, id: vehicle.id),
                                systemImage: type.symbol
                            )
                            .font(.gg(12, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        }
                        Text(vehicleStatus(vehicle))
                            .font(.gg(11, .bold))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Button {
                            if let route {
                                assignError = session.perform(
                                    .unassignVehicleFromRoute(routeID: route.id, vehicleID: vehicle.id)
                                )
                            }
                        } label: {
                            Text("Release")
                                .font(.gg(11, .heavy))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().stroke(Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                Button { showsAssignSheet = true } label: {
                    Text(assignedVehicles.isEmpty ? "Assign Vehicle" : "Assign Another Vehicle")
                        .font(.gg(12, .heavy))
                        .foregroundStyle(assignedVehicles.isEmpty ? Theme.onBrand : accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            Capsule().fill(assignedVehicles.isEmpty ? accent : accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                // Safe close: stop new loads, let committed freight finish.
                if contract.cancellationRequestedAt == nil {
                    Button {
                        assignError = session.perform(.cancelContract(contract.id))
                    } label: {
                        Text("End")
                            .font(.gg(12, .heavy))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 9)
                            .background(Capsule().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Closing")
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 10)
                }
            }
        }
        .padding(14)
        .surfacePanel(cornerRadius: 16)
        .sheet(isPresented: $showsAssignSheet) {
            ContractAssignSheet(contract: contract, accent: accent)
        }
        .alert(
            "Could Not Update Assignment",
            isPresented: Binding(get: { assignError != nil }, set: { if !$0 { assignError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The vehicle or contract is no longer available.")
        }
    }

    private func vehicleStatus(_ vehicle: Vehicle) -> String {
        if let run = session.state?.routeRun(for: vehicle.id) {
            switch run.phase {
            case .traveling: return String(localized: "driving")
            case .servicing: return String(localized: "at the dock")
            case .waiting: return String(localized: "waiting for cargo")
            }
        }
        if let job = session.state?.activeJob(for: vehicle.id) {
            switch job.phase {
            case .deadheading: return String(localized: "to pickup")
            case .loading: return String(localized: "loading")
            case .enRoute: return String(localized: "en route")
            case .unloading: return String(localized: "unloading")
            }
        }
        let city = session.catalog.city(vehicle.cityID)?.name ?? ""
        return String(localized: "standby · \(city)")
    }

}

/// One-tap vehicle assignment for a signed contract. Lists every vehicle with
/// its fit and projected per-shipment cycle profit on this lane.
struct ContractAssignSheet: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let contract: ActiveContract
    var accent: Color
    @State private var assignError: CommandError?

    private var candidates: [Vehicle] {
        guard let state = session.state else { return [] }
        return state.vehicles.filter { state.route(of: $0.id) == nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The vehicle loops this lane automatically: pick up at \(session.cityName(contract.origin)), deliver to \(session.cityName(contract.destination)), return empty, wait for the next shipment.")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.08)))

                    if candidates.isEmpty {
                        Text("Every vehicle already serves a route. Buy a new vehicle or release one first.")
                            .font(.gg(12.5, .bold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .surfacePanel()
                    }
                    ForEach(candidates) { vehicle in
                        let estimate = session.estimate(contract: contract, vehicle: vehicle)
                        Button {
                            if let error = session.perform(
                                .assignVehicleToContract(contractID: contract.id, vehicleID: vehicle.id)
                            ) {
                                assignError = error
                            } else {
                                dismiss()
                            }
                        } label: {
                            candidateRow(vehicle: vehicle, estimate: estimate)
                        }
                        .buttonStyle(.plain)
                        .disabled(estimate == nil)
                    }
                }
                .padding(16)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationTitle("Assign Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert(
                "Could Not Assign Vehicle",
                isPresented: Binding(get: { assignError != nil }, set: { if !$0 { assignError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(assignErrorMessage)
            }
        }
        .tint(accent)
    }

    @ViewBuilder
    private func candidateRow(vehicle: Vehicle, estimate: SimulationEngine.ContractEstimate?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let type = session.catalog.vehicleType(vehicle.typeID) {
                    Label(
                        Format.vehicleCode(typeName: type.name, id: vehicle.id),
                        systemImage: type.symbol
                    )
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                }
                Text("· \(session.catalog.city(vehicle.cityID)?.name ?? "")")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if session.state?.isVehicleIdle(vehicle.id) == false {
                    TagPill(text: String(localized: "Busy"), color: Theme.warning)
                }
            }
            if let estimate {
                HStack(spacing: 12) {
                    Text("Profit \(Format.money(estimate.profitPerShipment)) / shipment")
                        .foregroundStyle(estimate.profitPerShipment >= 0 ? Theme.mint : Theme.coral)
                    Text("cycle \(Format.duration(minutes: estimate.cycleMinutes))")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.gg(11.5, .bold))
                if session.state?.isVehicleIdle(vehicle.id) == false {
                    Text("Joins the route after finishing its current job.")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                Text("Shipment load does not fit this vehicle.")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(15)
        .surfacePanel()
        .contentShape(Rectangle())
    }

    private var assignErrorMessage: LocalizedStringKey {
        switch assignError {
        case .vehicleAlreadyAssigned: "That vehicle already serves another route."
        case .loadExceedsCapacity: "The shipment load does not fit that vehicle."
        default: "The vehicle or contract is no longer available."
        }
    }

}

// MARK: - Offer detail & acceptance

