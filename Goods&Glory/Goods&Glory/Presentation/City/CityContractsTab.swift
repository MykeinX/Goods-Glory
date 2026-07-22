//
//  CityContractsTab.swift
//  Goods&Glory
//
//  Lanes that can be signed here. A branch is the gate: without one the tab
//  says so plainly instead of showing an empty list.
//

import SwiftUI

struct CityContractsTab: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID

    @State private var commandError: CommandError?

    private var accent: Color { session.accentColor }

    private var offers: [ContractOffer] {
        (session.state?.contractOffers ?? [])
            .filter { $0.origin == cityID }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let state = session.state {
                if state.hasOperationalOffice(in: cityID) {
                    SectionLabel(String(localized: "On offer \(offers.count)"))
                    if offers.isEmpty {
                        // Why it is empty matters more than that it is empty:
                        // the board is a consequence of what the player hauls.
                        note(String(
                            localized: "Nothing offered yet. Firms commit part of a lane's output to carriers they have watched deliver — haul freight out of this city and the offers follow."
                        ))
                    } else {
                        ForEach(offers) { offer in
                            offerCard(offer)
                        }
                    }
                } else if let quote = session.quote(kind: .office, level: 1, city: cityID) {
                    SectionLabel(String(localized: "Branch required"))
                    note(String(
                        localized: "A branch here unlocks contract lanes out of \(session.cityName(cityID)). \(Format.money(quote.cost)) · \(Format.duration(minutes: quote.buildMinutes)) to build."
                    ))
                }
            }
        }
        .alert(
            "Could Not Sign",
            isPresented: Binding(
                get: { commandError != nil },
                set: { if !$0 { commandError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CommandErrorMessage.text(commandError))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.gg(12, .bold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .surfacePanel(cornerRadius: 18)
    }

    private func offerCard(_ offer: ContractOffer) -> some View {
        let drops = offer.destinations.map { session.cityName($0.cityID) }
        let lane = drops.count > 1 ? "\(drops[0]) +\(drops.count - 1)" : (drops.first ?? "—")
        let brief = session.brief(for: offer)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: session.productSymbol(offer.productID))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                Text("→ \(lane)")
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                TagPill(
                    text: ContractArchetypeDisplay.label(offer.archetype),
                    color: ContractArchetypeDisplay.color(offer.archetype)
                )
            }

            if let brief {
                ContractHeadline(
                    brief: brief,
                    accent: accent,
                    commitment: session.commitmentLoad(adding: offer)
                )
            }

            HStack(spacing: 7) {
                if let brief {
                    StatChip(
                        symbol: "truck.box.fill",
                        text: "\(Int((brief.fleetLoad * 100).rounded()))%",
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

            HStack {
                if let brief, brief.penaltyPerParcel > 0 {
                    Text("Late load costs \(Format.money(brief.penaltyPerParcel))")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button {
                    commandError = session.perform(.signContract(offer.id))
                } label: {
                    Text("Sign")
                        .font(.gg(12, .heavy))
                        .foregroundStyle(Theme.onBrand)
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .surfacePanel(cornerRadius: 18)
    }
}
