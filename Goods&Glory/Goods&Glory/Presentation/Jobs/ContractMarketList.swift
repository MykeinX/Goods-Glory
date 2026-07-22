//
//  ContractMarketList.swift
//  Goods&Glory
//
//  Contracts on offer: what the market will commit to, and at what price.
//

import SwiftUI

struct ContractMarketList: View {
    @Environment(GameSession.self) private var session
    var accent: Color
    @State private var signError: CommandError?

    private var openOffers: [ContractOffer] {
        (session.state?.contractOffers ?? []).sorted { $0.expiresAt < $1.expiresAt }
    }

    /// Evergreen contracts have no end date, so they sort last behind the
    /// fixed-term ones the player has to act on first.
    private var active: [ActiveContract] {
        (session.state?.activeContracts ?? []).sorted {
            ($0.endsAt?.totalMinutes ?? .max) < ($1.endsAt?.totalMinutes ?? .max)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !active.isEmpty {
                SectionLabel(String(localized: "Active contracts"))
                ForEach(active) { contract in
                    ActiveContractRow(contract: contract, accent: accent)
                }
            }

            SectionLabel(String(localized: "Open contracts"))
            if openOffers.isEmpty {
                Text("No open contracts. New lanes appear as time passes.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .surfacePanel()
            } else {
                ForEach(openOffers) { offer in
                    ContractOfferRow(offer: offer, accent: accent) {
                        if let error = session.perform(.signContract(offer.id)) {
                            signError = error
                        }
                    }
                }
            }
        }
        .alert(
            "Could Not Sign Contract",
            isPresented: Binding(get: { signError != nil }, set: { if !$0 { signError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("That contract is no longer available.")
        }
    }
}

struct ContractOfferRow: View {
    @Environment(GameSession.self) private var session
    let offer: ContractOffer
    var accent: Color
    var onSign: () -> Void

    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            laneHeader
            headline
            statChips
            if showsDetail { detailBlock }
            actions
        }
        .padding(14)
        .surfacePanel()
    }

    // MARK: Lane

    private var laneHeader: some View {
        HStack(spacing: 9) {
            Image(systemName: session.catalog.product(offer.productID)?.symbol ?? "shippingbox.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(accent.opacity(0.14))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(laneTitle)
                    .font(.gg(14.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(Format.distance(km: offer.distanceKm))
                    .font(.gg(10.5, .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 4)
            TagPill(text: archetypeLabel, color: archetypeColor)
        }
    }

    // MARK: The two numbers that decide it

    /// What the commitment reserves, and what it adds over carrying the same
    /// freight unsigned. Not a standalone profit line: this freight is already
    /// on the map, so the question is what signing changes.
    @ViewBuilder private var headline: some View {
        if let brief = session.brief(for: offer) {
            ContractHeadline(
                brief: brief,
                accent: accent,
                commitment: session.commitmentLoad(adding: offer)
            )
        }
    }

    /// Three icons, three numbers: fleet tied up, rhythm, commitment.
    @ViewBuilder private var statChips: some View {
        let brief = session.brief(for: offer)
        HStack(spacing: 7) {
            if let brief {
                StatChip(
                    symbol: "truck.box.fill",
                    text: "×\(brief.vehiclesNeeded)",
                    tint: accent
                )
            }
            StatChip(
                symbol: "arrow.triangle.2.circlepath",
                text: Format.shortDuration(minutes: offer.shipmentIntervalMinutes),
                tint: Theme.sky
            )
            StatChip(
                symbol: offer.durationDays == nil ? "infinity" : "calendar",
                text: offer.durationDays.map { "\($0) d" } ?? "∞",
                tint: Theme.textSecondary
            )
            Spacer(minLength: 0)
        }
    }

    // MARK: Detail, only when asked for

    @ViewBuilder private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            detailRow(
                String(localized: "Each cycle"),
                "\(offer.parcelsPerCycle) × \(Format.mass(kg: offer.parcelMassKg))"
            )
            // What signing actually does: it locks part of a lane the player
            // can already see on the map, and that share stops arriving at the
            // dock as spot freight.
            ForEach(offer.destinations, id: \.laneID) { destination in
                detailRow(
                    String(localized: "Locks of \(session.cityName(destination.cityID)) lane"),
                    "\(Int((Double(destination.committedShareBps) / 100).rounded()))%"
                )
            }
            detailRow(
                String(localized: "Time to prepare"),
                Format.duration(minutes: offer.leadTimeMinutes)
            )
            detailRow(
                String(localized: "Deadline per load"),
                Format.duration(minutes: offer.deliveryWindowMinutes)
            )
            if let brief = session.brief(for: offer) {
                detailRow(
                    String(localized: "Ties up"),
                    String(localized: "\(Int((brief.fleetLoad * 100).rounded()))% of a truck")
                )
                detailRow(
                    String(localized: "Late load costs"),
                    Format.money(brief.penaltyPerParcel)
                )
            }
            if let address = session.addressLine(from: offer.originFirmID, to: offer.destinationFirmID) {
                detailRow(String(localized: "Customer"), address)
            }
        }
        .padding(.top, 2)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.gg(10.5, .bold))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.gg(10.5, .heavy))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.easeInOut(duration: 0.18)) { showsDetail.toggle() } } label: {
                Image(systemName: showsDetail ? "chevron.up" : "ellipsis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, height: 34)
                    .background(Capsule().stroke(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button(action: onSign) {
                Text("Sign")
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.onBrand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Capsule().fill(accent))
            }
            .buttonStyle(.plain)
        }
    }

    private var laneTitle: String {
        let origin = session.cityName(offer.origin)
        let drops = offer.destinations.map { session.cityName($0.cityID) }
        guard drops.count > 1 else { return "\(origin) → \(drops.first ?? "—")" }
        return "\(origin) → \(drops[0]) +\(drops.count - 1)"
    }

    private var archetypeLabel: String { ContractArchetypeDisplay.label(offer.archetype) }

    private var archetypeColor: Color { ContractArchetypeDisplay.color(offer.archetype) }

}

