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
    private var accent: Color { session.accentColor }


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
    private var accent: Color { session.accentColor }


    /// HQ first, then the rest in stable city order. One card per site; the
    /// modules on it are what make sites differ.
    private var facilities: [Facility] {
        (session.state?.facilities ?? []).sorted { lhs, rhs in
            if lhs.isHeadquarters != rhs.isHeadquarters { return lhs.isHeadquarters }
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
        case .dependentModuleExists(let kind):
            "Remove the \(Format.moduleName(kind).lowercased()) first — it is built onto this."
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

    @State private var moduleToRemove: FacilityModuleKind?

    private var cityName: String {
        session.catalog.city(facility.cityID)?.name ?? facility.cityID.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ForEach(FacilityModuleKind.installOrder, id: \.self) { kind in
                if let module = facility.module(kind) {
                    moduleRow(kind, module: module)
                }
            }
        }
        .padding(14)
        .surfacePanel(cornerRadius: 18)
        .confirmationDialog(
            "Remove this module?",
            isPresented: Binding(
                get: { moduleToRemove != nil },
                set: { if !$0 { moduleToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let kind = moduleToRemove {
                    perform(.removeModule(kind: kind, cityID: facility.cityID))
                }
                moduleToRemove = nil
            }
            Button("Keep", role: .cancel) { moduleToRemove = nil }
        } message: {
            Text("You get nothing back. Removing the office also stops contracts from this city.")
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: facility.isHeadquarters ? "star.fill" : "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(cityName)
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(facility.isHeadquarters
                     ? String(localized: "Headquarters · \(facility.modules.count) module(s)")
                     : String(localized: "\(facility.modules.count) module(s)"))
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Text("\(Format.money(siteUpkeep)) / day")
                .font(.gg(11, .heavy))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var siteUpkeep: Money {
        facility.modules.reduce(0) { total, module in
            total + (session.quote(
                kind: module.kind, level: module.level, city: facility.cityID
            )?.upkeepPerDay ?? 0)
        }
    }

    @ViewBuilder private func moduleRow(_ kind: FacilityModuleKind, module: FacilityModule) -> some View {
        let clock = session.state?.clock ?? .start
        let operational = module.isOperational(at: clock)
        let tint: Color = kind == .office ? Theme.sky : (kind == .warehouse ? Theme.mint : Theme.warning)
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: Format.moduleSymbol(kind))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                Text("\(Format.moduleName(kind)) · Lv \(module.level)")
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 4)
                if !operational {
                    progressLine(String(localized: "\(Format.shortDuration(minutes: clock.minutes(until: module.operationalAt))) to open"))
                } else if let target = module.upgradingTo, let endsAt = module.upgradeEndsAt {
                    progressLine(String(localized: "Lv \(target) in \(Format.shortDuration(minutes: clock.minutes(until: endsAt)))"))
                }
            }

            if kind == .warehouse, operational { storageBar }
            if kind == .office, operational {
                Text("\(openContractCount) contract lane(s) on offer here")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }

            if operational, !module.isUpgrading {
                HStack(spacing: 8) {
                    if let upgrade = session.upgradeQuote(for: module, in: facility.cityID) {
                        Button {
                            perform(.upgradeModule(kind: kind, cityID: facility.cityID))
                        } label: {
                            Text("Upgrade to \(upgrade.level) · \(Format.money(upgrade.cost))")
                                .font(.gg(11, .heavy))
                                .foregroundStyle(Theme.onBrand)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(accent))
                        }
                        .buttonStyle(.plain)
                    }
                    if !(facility.isHeadquarters && kind == .office) {
                        Button { moduleToRemove = kind } label: {
                            Text("Remove")
                                .font(.gg(11, .heavy))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Capsule().stroke(Theme.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface.opacity(0.5))
        )
    }

    private var openContractCount: Int {
        (session.state?.contractOffers ?? []).count { $0.origin == facility.cityID }
    }

    private func progressLine(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "hammer.fill")
                .font(.caption2)
            Text(text)
                .font(.gg(10.5, .bold))
        }
        .foregroundStyle(accent)
    }

    @ViewBuilder private var storageBar: some View {
        if let state = session.state {
            // Capacity from the engine, not from the warehouse level alone:
            // racking adds tonnage to the same building, and a bar that ignored
            // it would disagree with the rule that decides what fits.
            let capacity = session.storageCapacity(of: facility)
            let used = state.storedLoad(in: facility.id)
            let massFill = capacity.massKg > 0
                ? Double(used.massKg) / Double(capacity.massKg) : 0
            let volumeFill = capacity.volumeM3 > 0
                ? used.volumeM3 / capacity.volumeM3 : 0
            VStack(alignment: .leading, spacing: 4) {
                // Mass and volume fill independently; whichever runs out first
                // is the real constraint, so the bar shows the worse of the two.
                ThemeProgressBar(value: max(massFill, volumeFill), tint: Theme.mint, height: 5)
                Text("\(Format.mass(kg: used.massKg)) / \(Format.mass(kg: capacity.massKg)) · \(state.shipments(storedIn: facility.id).count) parcel(s)")
                    .font(.gg(10.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
