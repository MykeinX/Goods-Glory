//
//  CityJobCard.swift
//  Goods&Glory
//
//  One waiting parcel, told as a card rather than a spreadsheet row. The old
//  row listed destination, mass, distance and time in one grey string, so every
//  job looked like every other job. Here the three things a dispatcher actually
//  compares — what it pays, how hard it is, how much time is left — each get
//  their own weight, and the card opens in place to pick the truck.
//

import SwiftUI

struct CityJobCard: View {
    @Environment(GameSession.self) private var session
    let offer: JobOffer
    /// Shared with the map: the expanded card is the parcel drawn as an arc.
    @Binding var previewOfferID: JobID?
    var onError: (CommandError) -> Void

    @State private var selectedVehicleID: VehicleID?

    private var accent: Color { session.accentColor }
    private var isExpanded: Bool { previewOfferID == offer.id }

    private var destinationName: String { session.cityName(offer.destination) }

    /// How much of the parcel's window is gone, 0...1. Drives every tint here.
    private var timeSpent: Double {
        let clock = session.state?.clock ?? .start
        let window = max(1, offer.createdAt.minutes(until: offer.expiresAt))
        let remaining = max(0, clock.minutes(until: offer.expiresAt))
        return min(1, max(0, 1 - Double(remaining) / Double(window)))
    }

    private var minutesLeft: Int {
        max(0, (session.state?.clock ?? .start).minutes(until: offer.expiresAt))
    }

    private var urgencyTint: Color {
        timeSpent >= 0.85 ? Theme.coral : (timeSpent >= 0.5 ? Theme.warning : Theme.mint)
    }

    /// Idle trucks standing in this city that can physically take the load,
    /// best margin first — the order the player would pick in anyway.
    private var candidates: [(vehicle: Vehicle, estimate: SimulationEngine.JobEstimate)] {
        guard let state = session.state else { return [] }
        let busy = state.busyVehicleIDs()
        return state.vehicles
            .filter { $0.cityID == offer.origin && !busy.contains($0.id) }
            .compactMap { vehicle in
                session.estimate(offer: offer, vehicle: vehicle)
                    .map { (vehicle: vehicle, estimate: $0) }
            }
            .sorted { $0.estimate.estimatedProfit > $1.estimate.estimatedProfit }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                toggle()
            } label: {
                summary
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Theme.stroke)
                vehiclePicker
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isExpanded ? accent.opacity(0.5) : urgencyTint.opacity(0.22), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: isExpanded)
    }

    // MARK: Collapsed summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(urgencyTint.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: session.productSymbol(offer.productID))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(urgencyTint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("→ \(destinationName)")
                            .font(.gg(15, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if offer.source == .contract {
                            TagPill(text: String(localized: "Contract"), color: Theme.sky)
                        }
                    }
                    Text("\(session.productName(offer.productID)) · \(Format.mass(kg: offer.load.massKg))")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.money(offer.payout))
                        .font(.gg(17, .heavy))
                        .foregroundStyle(Theme.mint)
                        .monospacedDigit()
                    Text("\(Format.money(offer.payoutPerKm))/km")
                        .font(.gg(10, .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 7) {
                StatChip(
                    symbol: "arrow.left.and.right",
                    text: Format.distance(km: offer.distanceKm),
                    tint: Theme.textSecondary
                )
                StatChip(
                    symbol: "clock.fill",
                    text: Format.shortDuration(minutes: minutesLeft),
                    tint: urgencyTint
                )
                Spacer(minLength: 4)
                availabilityLabel
            }

            ThemeProgressBar(value: timeSpent, tint: urgencyTint, height: 4)
        }
        .contentShape(Rectangle())
    }

    private var availabilityLabel: some View {
        let count = candidates.count
        return HStack(spacing: 4) {
            Image(systemName: count > 0 ? "truck.box.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .heavy))
            Text(count > 0
                 ? String(localized: "\(count) can take it")
                 : String(localized: "No truck here"))
                .font(.gg(11, .heavy))
        }
        .foregroundStyle(count > 0 ? accent : Theme.textTertiary)
    }

    // MARK: Expanded vehicle picker

    @ViewBuilder private var vehiclePicker: some View {
        let options = candidates
        if options.isEmpty {
            Text("No idle truck in \(session.cityName(offer.origin)) fits this load. Send one here first.")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 6) {
                ForEach(options, id: \.vehicle.id) { option in
                    Button {
                        selectedVehicleID = option.vehicle.id
                    } label: {
                        CityVehicleChoiceRow(
                            vehicle: option.vehicle,
                            estimate: option.estimate,
                            isSelected: selectedVehicleID == option.vehicle.id,
                            accent: accent
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                accept()
            } label: {
                Text("Accept Job")
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.onBrand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedVehicleID == nil)
            .opacity(selectedVehicleID == nil ? 0.45 : 1)
        }
    }

    // MARK: Actions

    private func toggle() {
        if isExpanded {
            previewOfferID = nil
        } else {
            previewOfferID = offer.id
            selectedVehicleID = candidates.first?.vehicle.id
        }
    }

    private func accept() {
        guard let selectedVehicleID else { return }
        if let error = session.perform(.acceptJob(offerID: offer.id, vehicleID: selectedVehicleID)) {
            onError(error)
        } else {
            previewOfferID = nil
        }
    }
}

/// One truck as an option for a parcel: what it would earn and how long it takes.
struct CityVehicleChoiceRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    let estimate: SimulationEngine.JobEstimate
    let isSelected: Bool
    var accent: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(isSelected ? accent : Theme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.vehicleCode(vehicle))
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(Format.duration(minutes: estimate.totalMinutes))
                    .font(.gg(10.5, .bold))
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.money(estimate.estimatedProfit))
                    .font(.gg(13, .heavy))
                    .foregroundStyle(estimate.estimatedProfit >= 0 ? Theme.mint : Theme.coral)
                    .monospacedDigit()
                Text("net")
                    .font(.gg(9.5, .heavy))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? accent.opacity(0.12) : Theme.backgroundTop.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.45) : Theme.strokeSoft, lineWidth: 1)
        )
    }
}
