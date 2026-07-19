//
//  FacilitiesView.swift
//  Goods&Glory
//
//  Facilities tab: the company's real estate. Branches unlock contract
//  business in their city; warehouses store and consolidate freight.
//  Construction itself starts from the city screen — you build somewhere,
//  not in the abstract — so this tab is the portfolio and upgrade view.
//

import SwiftUI

struct FacilitiesView: View {
    @Environment(GameSession.self) private var session

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            FacilitiesContent()
        }
        .tint(accent)
    }
}

/// Shared list content used by the Facilities tab and Company → Facilities.
struct FacilitiesContent: View {
    @Environment(GameSession.self) private var session
    @State private var commandError: CommandError?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    /// HQ first, then branches, then warehouses; stable city order within each.
    private var facilities: [Facility] {
        (session.state?.facilities ?? []).sorted { lhs, rhs in
            if lhs.isHeadquarters != rhs.isHeadquarters { return lhs.isHeadquarters }
            if lhs.kind != rhs.kind { return lhs.kind == .branch }
            return lhs.cityID.rawValue < rhs.cityID.rawValue
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(title: "Facilities", trailing: upkeepSummary)

                if facilities.isEmpty {
                    emptyState
                } else {
                    ForEach(facilities) { facility in
                        FacilityCard(facility: facility, accent: accent) { command in
                            commandError = session.perform(command)
                        }
                    }
                }

                hint

                Color.clear.frame(height: Layout.tabBarClearance)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .alert(
            "Could Not Complete That",
            isPresented: Binding(get: { commandError != nil }, set: { if !$0 { commandError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var upkeepSummary: String {
        let upkeep = session.facilityUpkeepPerDay()
        guard upkeep > 0 else { return String(localized: "No upkeep yet") }
        return String(localized: "\(Format.money(upkeep)) / day upkeep")
    }

    @ViewBuilder private var emptyState: some View {
        Text("No facilities yet.")
            .font(.gg(12.5, .bold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .surfacePanel()
    }

    private var hint: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
            Text("To build, open a city on the map — price and build time depend on where you build.")
                .font(.gg(11.5, .bold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(0.08))
        )
    }

    private var errorMessage: LocalizedStringKey {
        switch commandError {
        case .insufficientFunds(let required): "You need \(Format.money(required)) for this."
        case .facilityAlreadyExists: "You already have that building here."
        case .facilityNotAvailable: "It is still under construction or already at its top level."
        case .warehouseNotEmpty: "Move the stored freight out first."
        case .cannotDemolishHeadquarters: "Headquarters cannot be demolished."
        default: "That building is no longer available."
        }
    }
}

// MARK: - Facility card

private struct FacilityCard: View {
    @Environment(GameSession.self) private var session
    let facility: Facility
    var accent: Color
    var perform: (GameCommand) -> Void

    @State private var confirmsDemolition = false

    private var cityName: String {
        session.catalog.city(facility.cityID)?.name ?? facility.cityID.rawValue
    }

    private var isOperational: Bool {
        session.state.map { facility.isOperational(at: $0.clock) } ?? false
    }

    private var tint: Color {
        facility.kind == .branch ? Theme.sky : Theme.mint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            statusLine
            if facility.kind == .warehouse, isOperational {
                storageBar
            }
            actions
        }
        .padding(14)
        .surfacePanel(cornerRadius: 18)
        .confirmationDialog(
            "Demolish this facility?",
            isPresented: $confirmsDemolition,
            titleVisibility: .visible
        ) {
            Button("Demolish", role: .destructive) {
                perform(.demolishFacility(facility.id))
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("You get nothing back, and contracts from this city stop being offered.")
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: facility.kind == .branch ? "building.2.fill" : "shippingbox.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.gg(13.5, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(cityName)
                        .font(.gg(11, .heavy))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text("Level \(facility.level)")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            if let quote = session.quote(kind: facility.kind, level: facility.level, city: facility.cityID) {
                Text("\(Format.money(quote.upkeepPerDay)) / day")
                    .font(.gg(11, .heavy))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var title: String {
        if facility.isHeadquarters { return String(localized: "Headquarters") }
        return facility.kind == .branch
            ? String(localized: "Branch")
            : String(localized: "Warehouse")
    }

    @ViewBuilder private var statusLine: some View {
        if let clock = session.state?.clock {
            if !isOperational {
                progressLine(
                    text: String(localized: "Under construction — \(Format.duration(minutes: clock.minutes(until: facility.operationalAt))) left")
                )
            } else if let target = facility.upgradingTo, let endsAt = facility.upgradeEndsAt {
                progressLine(
                    text: String(localized: "Upgrading to level \(target) — \(Format.duration(minutes: clock.minutes(until: endsAt))) left")
                )
            } else if facility.kind == .branch {
                Text("\(openContractCount) contract lane(s) on offer here")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var openContractCount: Int {
        (session.state?.contractOffers ?? []).count { $0.origin == facility.cityID }
    }

    private func progressLine(text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "hammer.fill")
                .font(.caption2)
                .foregroundStyle(accent)
            Text(text)
                .font(.gg(11.5, .bold))
                .foregroundStyle(accent)
        }
    }

    @ViewBuilder private var storageBar: some View {
        if let state = session.state,
           let quote = session.quote(kind: .warehouse, level: facility.level, city: facility.cityID) {
            let used = state.storedLoad(in: facility.id)
            let massFill = quote.storage.massKg > 0
                ? Double(used.massKg) / Double(quote.storage.massKg) : 0
            let volumeFill = quote.storage.volumeM3 > 0
                ? used.volumeM3 / quote.storage.volumeM3 : 0
            VStack(alignment: .leading, spacing: 5) {
                // Mass and volume fill independently; whichever runs out first
                // is the real constraint, so the bar shows the worse of the two.
                ThemeProgressBar(value: max(massFill, volumeFill), tint: tint, height: 5)
                Text("\(Format.mass(kg: used.massKg)) / \(Format.mass(kg: quote.storage.massKg)) · \(state.shipments(storedIn: facility.id).count) parcel(s)")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if isOperational, !facility.isUpgrading,
               let upgrade = session.upgradeQuote(for: facility) {
                Button { perform(.upgradeFacility(facility.id)) } label: {
                    Text("Upgrade to \(upgrade.level) · \(Format.money(upgrade.cost))")
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.onBrand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
            if !facility.isHeadquarters {
                Button { confirmsDemolition = true } label: {
                    Text("Demolish")
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().stroke(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
