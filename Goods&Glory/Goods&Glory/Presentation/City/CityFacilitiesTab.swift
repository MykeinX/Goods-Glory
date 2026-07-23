//
//  CityFacilitiesTab.swift
//  Goods&Glory
//
//  What the company owns and parks in this city: the warehouse and what sits
//  in it, the buildings that can be raised or upgraded, and the trucks here.
//

import SwiftUI

struct CityFacilitiesTab: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID

    @State private var buildError: CommandError?

    private var accent: Color { session.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            warehouseSection
            SectionLabel(String(localized: "Your site here"))
            siteTree
            vehiclesSection
        }
        .alert(
            "Could Not Build",
            isPresented: Binding(
                get: { buildError != nil },
                set: { if !$0 { buildError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CommandErrorMessage.text(buildError))
        }
    }

    // MARK: Warehouse

    /// What sits in this city's warehouse, grouped the way a dispatcher thinks:
    /// same product and same final destination.
    @ViewBuilder private var warehouseSection: some View {
        if let state = session.state,
           let warehouse = state.warehouseSite(in: cityID),
           let module = warehouse.operationalModule(.warehouse, at: state.clock) {
            let lots = state.storageLots(in: warehouse.id)
            SectionLabel(String(localized: "Warehouse · level \(module.level)"))
            VStack(alignment: .leading, spacing: 9) {
                // Capacity comes from the engine: the shell plus whatever is
                // racked into it, so the bar never disagrees with the rule that
                // decides whether a parcel actually fits.
                let capacity = session.storageCapacity(of: warehouse)
                if capacity.massKg > 0 {
                    let used = state.storedLoad(in: warehouse.id)
                    let fill = Double(used.massKg) / Double(capacity.massKg)
                    ThemeProgressBar(value: min(1, fill), tint: Theme.mint, height: 5)
                    Text("\(Format.mass(kg: used.massKg)) / \(Format.mass(kg: capacity.massKg)) stored")
                        .font(.gg(11, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                if lots.isEmpty {
                    Text("Empty — route freight here to consolidate it.")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(lots) { lot in
                        lotRow(lot)
                    }
                }
            }
            .padding(13)
            .surfacePanel(cornerRadius: 18)
        }
    }

    private func lotRow(_ lot: StorageLot) -> some View {
        let clock = session.state?.clock ?? .start
        return HStack(spacing: 10) {
            Image(systemName: session.productSymbol(lot.key.productID))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("→ \(session.cityName(lot.key.destinationCityID)) · \(Format.mass(kg: lot.load.massKg))")
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(lotDetail(lot, clock: clock))
                    .font(.gg(10.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Text("\(lot.parcelCount)")
                .font(.gg(12, .heavy))
                .foregroundStyle(accent)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private func lotDetail(_ lot: StorageLot, clock: GameTime) -> String {
        let product = session.productName(lot.key.productID)
        guard let deadline = lot.earliestDeadline else { return product }
        let remaining = max(0, clock.minutes(until: deadline))
        return "\(product) · \(Format.duration(minutes: remaining)) left · \(Format.money(lot.pendingPayout))"
    }

    // MARK: Buildings

    /// The site as it is actually built: the office first, and each module's
    /// add-ons indented under the thing they are bolted to. A module whose
    /// parent does not exist is not offered at all — a loading dock in a city
    /// with no warehouse is not a choice, it is a nonsense.
    @ViewBuilder private var siteTree: some View {
        if let state = session.state {
            ForEach(FacilityModuleKind.installOrder, id: \.self) { kind in
                let parentBuilt = kind.requires.map { state.module($0, in: cityID) != nil } ?? true
                if parentBuilt {
                    HStack(alignment: .top, spacing: 8) {
                        if kind.depth > 0 {
                            // Indent rail: this stands on the module above it.
                            Rectangle()
                                .fill(Theme.stroke)
                                .frame(width: 1)
                                .padding(.leading, CGFloat(kind.depth) * 12)
                                .padding(.vertical, 6)
                        }
                        moduleRow(kind, state: state)
                    }
                }
            }
        }
    }

    @ViewBuilder private func moduleRow(_ kind: FacilityModuleKind, state: GameState) -> some View {
        if let module = state.module(kind, in: cityID) {
            installedModuleRow(kind, module: module, state: state)
        } else if let quote = session.quote(kind: kind, level: 1, city: cityID) {
            installOfferRow(kind: kind, quote: quote, cash: state.cash)
        }
    }

    private func installedModuleRow(
        _ kind: FacilityModuleKind,
        module: FacilityModule,
        state: GameState
    ) -> some View {
        let operational = module.isOperational(at: state.clock)
        let isHQOffice = kind == .office
            && state.facility(in: cityID)?.isHeadquarters == true
        let tint: Color = kind == .office ? Theme.sky : (kind == .warehouse ? Theme.mint : Theme.warning)
        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: Format.moduleSymbol(kind))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isHQOffice
                     ? String(localized: "Headquarters office · level \(module.level)")
                     : "\(Format.moduleName(kind)) · level \(module.level)")
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(operational
                     ? Format.moduleSummary(kind)
                     : String(localized: "Under construction — \(Format.duration(minutes: state.clock.minutes(until: module.operationalAt))) left"))
                    .font(.gg(11, .bold))
                    .foregroundStyle(operational ? Theme.textSecondary : accent)
            }
            Spacer(minLength: 4)
            if operational, !module.isUpgrading,
               let upgrade = session.upgradeQuote(for: module, in: cityID) {
                Button {
                    buildError = session.perform(.upgradeModule(kind: kind, cityID: cityID))
                } label: {
                    VStack(spacing: 1) {
                        Text("Lv \(module.level + 1)")
                            .font(.gg(11, .heavy))
                        Text(Format.money(upgrade.cost))
                            .font(.gg(9.5, .bold))
                    }
                    .foregroundStyle(state.cash >= upgrade.cost ? Theme.onBrand : Theme.textTertiary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(state.cash >= upgrade.cost ? accent : Theme.surface))
                }
                .buttonStyle(.plain)
                .disabled(state.cash < upgrade.cost)
            } else if module.isUpgrading, let endsAt = module.upgradeEndsAt {
                Text(Format.shortDuration(minutes: state.clock.minutes(until: endsAt)))
                    .font(.gg(10.5, .heavy))
                    .foregroundStyle(accent)
            }
        }
        .padding(12)
        .surfacePanel(cornerRadius: 18)
    }

    private func installOfferRow(
        kind: FacilityModuleKind,
        quote: FacilityQuote,
        cash: Money
    ) -> some View {
        let affordable = cash >= quote.cost
        return Button {
            buildError = session.perform(.installModule(kind: kind, cityID: cityID))
        } label: {
            HStack(spacing: 11) {
                Image(systemName: Format.moduleSymbol(kind))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(affordable ? accent : Theme.textTertiary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \(Format.moduleName(kind).lowercased())")
                        .font(.gg(12.5, .heavy))
                        .foregroundStyle(affordable ? Theme.textPrimary : Theme.textTertiary)
                    // Why it is worth the money, then what it costs here.
                    Text(Format.moduleSummary(kind))
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(Format.money(quote.cost)) · \(Format.duration(minutes: quote.buildMinutes)) to build · \(Format.money(quote.upkeepPerDay))/day")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(affordable ? Theme.textTertiary : Theme.coral)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.stroke.opacity(2))
            )
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }

    // MARK: Vehicles

    private var vehiclesSection: some View {
        let vehicles = session.state.map { state in
            state.vehicles.filter { state.physicalCity(of: $0) == cityID }
        } ?? []
        return VStack(alignment: .leading, spacing: 9) {
            SectionLabel(String(localized: "Vehicles in city \(vehicles.count)"))
                .padding(.top, 6)
            if vehicles.isEmpty {
                Text(String(localized: "No company vehicles here."))
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                // Horizontal scroll avoids SwiftUI.Layout conflict with app `Layout` enum.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(vehicles) { vehicle in
                            vehicleChip(vehicle)
                        }
                    }
                }
            }
        }
    }

    private func vehicleChip(_ vehicle: Vehicle) -> some View {
        let status = VehicleStatusDisplay.describe(vehicle, state: session.state)
        return HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text("\(session.vehicleCode(vehicle)) · \(status.label)")
                .font(.gg(12, .heavy))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 140 / 255, green: 170 / 255, blue: 215 / 255).opacity(0.12))
        )
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}
