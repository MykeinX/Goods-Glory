//
//  CityDetailView.swift
//  Goods&Glory
//
//  City detail (design 3c): map header with back control, sliding panel for
//  market/competition, outbound freight, facilities shell and local vehicles.
//

import SwiftUI

struct CityDetailView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var activeCityID: CityID
    @State private var mapSelection: MapSelection = .none
    @State private var buildError: CommandError?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    private var city: CityDefinition? { session.catalog.city(activeCityID) }

    init(cityID: CityID) {
        _activeCityID = State(initialValue: cityID)
        _mapSelection = State(initialValue: .city(cityID))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.backgroundTop.ignoresSafeArea()

            VStack(spacing: 0) {
                mapHeader
                panel
            }
        }
        .tint(accent)
        .onChange(of: mapSelection) { _, newValue in
            switch newValue {
            case .city(let id) where id != activeCityID:
                activeCityID = id
            case .vehicle, .none:
                // Detail map is city navigation only — keep the active city selected.
                mapSelection = .city(activeCityID)
            case .city:
                break
            }
        }
    }

    private var mapHeader: some View {
        ZStack(alignment: .topLeading) {
            if let state = session.state {
                InteractiveMapView(
                    catalog: session.catalog,
                    hqCityID: state.config.hqCity,
                    accentColorHex: state.config.identity.colorHex,
                    renderSnapshot: MapSceneAdapter.snapshot(
                        state: state,
                        catalog: session.catalog,
                        projection: MapProjection()
                    ),
                    cameraFocus: .city(activeCityID),
                    selection: $mapSelection
                )
            } else {
                Theme.backgroundTop
            }

            LinearGradient(colors: [Theme.backgroundTop, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 120)
                .allowsHitTesting(false)

            HStack(spacing: 10) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surfaceGlass))
                        .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                if let city {
                    HStack(spacing: 9) {
                        Text(city.name)
                            .font(.gg(24, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        TagPill(text: String(localized: "City"), color: Theme.sky)
                    }
                    .allowsHitTesting(false)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)
        }
        .frame(height: 330)
    }

    private var panel: some View {
        VStack(spacing: 9) {
            Capsule()
                .fill(Theme.stroke.opacity(1.5))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            if let city {
                let insight = CityInsight.make(city: city, catalog: session.catalog)
                Text(metaLine(for: city))
                    .font(.gg(12, .heavy))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)

                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 14) {
                            MetricBar(
                                label: String(localized: "Market Size"),
                                progress: insight.marketSizePercent,
                                tint: Theme.mint
                            )
                            MetricBar(
                                label: String(localized: "Competition"),
                                progress: insight.competitionPercent,
                                tint: Theme.coral
                            )
                        }
                        .padding(13)
                        .surfacePanel(cornerRadius: 20)

                        contractMarketSection
                        contractDutySection
                        warehouseSection
                        outboundFreightSection
                        facilitiesSection
                        vehiclesSection
                    }
                    .padding(.bottom, 36)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                .fill(Color(hex6: 0x101D31))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                        .stroke(Theme.stroke, lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.top, -26)
    }

    private func metaLine(for city: CityDefinition) -> String {
        let pop = city.population.formatted(.number.notation(.compactName))
        var parts = [city.country, String(localized: "\(pop) pop")]
        if session.state?.config.hqCity == city.id {
            parts.append(String(localized: "HQ"))
        } else if let hqID = session.state?.config.hqCity,
                  let route = session.catalog.shortestRoute(from: hqID, to: city.id) {
            let km = Int(route.distanceKm.rounded())
            parts.append(String(localized: "\(km) km from HQ"))
        }
        return parts.joined(separator: " · ")
    }

    /// Spot freight leaving this city. Hidden entirely when there is none —
    /// an empty list with an apology makes the world feel dead, and the player
    /// can already tell there is nothing here by its absence.
    @ViewBuilder private var outboundFreightSection: some View {
        let offers = (session.state?.offers ?? [])
            .filter { $0.origin == activeCityID && $0.source == .spot }
            .sorted { $0.expiresAt < $1.expiresAt }
        if !offers.isEmpty {
            SectionLabel(String(localized: "Outbound freight \(offers.count)"))
            ForEach(offers) { offer in
                freightRow(offer)
            }
        }
    }

    private func freightRow(_ offer: JobOffer) -> some View {
        let product = session.catalog.product(offer.productID)
        let dest = session.catalog.city(offer.destination)?.name ?? offer.destination.rawValue
        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: product?.symbol ?? "shippingbox.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "→ \(dest) · \(Format.mass(kg: offer.load.massKg))"))
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let address = contractAddressLine(for: offer) {
                    Text(address)
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Text(String(localized: "\(offer.source == .contract ? "Contract" : "Spot") · \(Format.money(offer.payout))"))
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Text(Format.money(offer.payout))
                .font(.gg(11.5, .heavy))
                .foregroundStyle(accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                )
        )
    }

    // MARK: Contract market

    /// Contracts that can be signed here. A branch is the gate: without one the
    /// section says so plainly instead of showing an empty list.
    @ViewBuilder private var contractMarketSection: some View {
        if let state = session.state {
            if state.hasOperationalBranch(in: activeCityID) {
                let offers = state.contractOffers
                    .filter { $0.origin == activeCityID }
                    .sorted { $0.expiresAt < $1.expiresAt }
                SectionLabel(String(localized: "Contracts from this city \(offers.count)"))
                if offers.isEmpty {
                    Text("No lanes on offer right now. New ones appear each day.")
                        .font(.gg(12, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .surfacePanel(cornerRadius: 18)
                } else {
                    ForEach(offers) { offer in
                        contractOfferRow(offer)
                    }
                }
            } else if let quote = session.quote(kind: .branch, level: 1, city: activeCityID) {
                SectionLabel(String(localized: "Contracts from this city"))
                Text("A branch here unlocks contract lanes out of \(city?.name ?? "this city"). \(Format.money(quote.cost)) · \(Format.duration(minutes: quote.buildMinutes)) to build.")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .surfacePanel(cornerRadius: 18)
            }
        }
    }

    private func contractOfferRow(_ offer: ContractOffer) -> some View {
        let product = session.catalog.product(offer.productID)
        let drops = offer.destinations.map {
            session.catalog.city($0.cityID)?.name ?? $0.cityID.rawValue
        }
        let lane = drops.count > 1 ? "\(drops[0]) +\(drops.count - 1)" : (drops.first ?? "—")
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: product?.symbol ?? "shippingbox.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                Text("→ \(lane)")
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                TagPill(text: archetypeLabel(offer.archetype), color: Theme.brand)
            }
            HStack(spacing: 7) {
                if let brief = session.brief(for: offer) {
                    StatChip(symbol: "truck.box.fill", text: "×\(brief.vehiclesNeeded)", tint: accent)
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
                if let brief = session.brief(for: offer) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.money(brief.profitPerDay))
                            .font(.gg(18, .heavy))
                            .foregroundStyle(brief.isViable ? Theme.mint : Theme.coral)
                            .monospacedDigit()
                        Text("/ day")
                            .font(.gg(10.5, .heavy))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                Button {
                    buildError = session.perform(.signContract(offer.id))
                } label: {
                    Text("Sign")
                        .font(.gg(12, .heavy))
                        .foregroundStyle(Theme.onBrand)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .surfacePanel(cornerRadius: 18)
    }

    private func archetypeLabel(_ archetype: ContractArchetype) -> String {
        switch archetype {
        case .laneRecurring: String(localized: "Lane")
        case .bulkPeriodic: String(localized: "Bulk")
        case .evergreen: String(localized: "Ongoing")
        case .multiDrop: String(localized: "Multi-drop")
        }
    }

    // MARK: Contract duty

    /// Contract loads this city owes right now. This is the screen the player
    /// lives in when running a network, so the deadline is front and centre.
    @ViewBuilder private var contractDutySection: some View {
        let due = (session.state?.offers ?? [])
            .filter { $0.source == .contract && $0.origin == activeCityID }
            .sorted { $0.expiresAt < $1.expiresAt }
        if !due.isEmpty {
            SectionLabel(String(localized: "Contract loads waiting here \(due.count)"))
            ForEach(due) { offer in
                dutyRow(offer)
            }
        }
    }

    private func dutyRow(_ offer: JobOffer) -> some View {
        let product = session.catalog.product(offer.productID)
        let destination = session.catalog.city(offer.destination)?.name ?? offer.destination.rawValue
        let clock = session.state?.clock ?? .start
        let remaining = max(0, clock.minutes(until: offer.expiresAt))
        let window = max(1, offer.createdAt.minutes(until: offer.expiresAt))
        let spent = 1 - Double(remaining) / Double(window)
        let tint: Color = spent >= 0.85 ? Theme.coral : (spent >= 0.5 ? accent : Theme.mint)

        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: product?.symbol ?? "shippingbox.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("→ \(destination) · \(Format.mass(kg: offer.load.massKg))")
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                ThemeProgressBar(value: min(1, max(0, spent)), tint: tint, height: 4)
                Text("\(Format.duration(minutes: remaining)) left · \(Format.money(offer.payout))")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: Warehouse

    /// What sits in this city's warehouse, grouped the way a dispatcher thinks:
    /// same product, same final destination, same contract.
    @ViewBuilder private var warehouseSection: some View {
        if let state = session.state,
           let warehouse = state.warehouse(in: activeCityID),
           warehouse.isOperational(at: state.clock) {
            let lots = state.storageLots(in: warehouse.id)
            SectionLabel(String(localized: "Warehouse · level \(warehouse.level)"))
            VStack(alignment: .leading, spacing: 9) {
                if let quote = session.quote(kind: .warehouse, level: warehouse.level, city: activeCityID) {
                    let used = state.storedLoad(in: warehouse.id)
                    let fill = quote.storage.massKg > 0
                        ? Double(used.massKg) / Double(quote.storage.massKg) : 0
                    ThemeProgressBar(value: min(1, fill), tint: Theme.mint, height: 5)
                    Text("\(Format.mass(kg: used.massKg)) / \(Format.mass(kg: quote.storage.massKg)) stored")
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
        let product = session.catalog.product(lot.key.productID)
        let destination = session.catalog.city(lot.key.destinationCityID)?.name
            ?? lot.key.destinationCityID.rawValue
        let clock = session.state?.clock ?? .start
        return HStack(spacing: 10) {
            Image(systemName: product?.symbol ?? "shippingbox.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("→ \(destination) · \(Format.mass(kg: lot.load.massKg))")
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
        let product = session.catalog.product(lot.key.productID)?.name ?? lot.key.productID.rawValue
        guard let deadline = lot.earliestDeadline else { return product }
        let remaining = max(0, clock.minutes(until: deadline))
        return "\(product) · \(Format.duration(minutes: remaining)) left · \(Format.money(lot.pendingPayout))"
    }

    // MARK: Buildings

    private var facilitiesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(String(localized: "Your buildings"))
            ForEach(FacilityKind.allCases, id: \.self) { kind in
                buildingRow(kind)
            }
        }
        .alert(
            "Could Not Build",
            isPresented: Binding(get: { buildError != nil }, set: { if !$0 { buildError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(buildErrorMessage)
        }
    }

    @ViewBuilder private func buildingRow(_ kind: FacilityKind) -> some View {
        if let state = session.state {
            if let facility = state.facility(kind: kind, in: activeCityID) {
                ownedBuildingRow(facility, state: state)
            } else if let quote = session.quote(kind: kind, level: 1, city: activeCityID) {
                buildOfferRow(kind: kind, quote: quote, cash: state.cash)
            }
        }
    }

    private func ownedBuildingRow(_ facility: Facility, state: GameState) -> some View {
        let operational = facility.isOperational(at: state.clock)
        let tint: Color = facility.kind == .branch ? Theme.sky : Theme.mint
        return HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: facility.kind == .branch ? "building.2.fill" : "shippingbox.fill")
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(facility.isHeadquarters
                     ? String(localized: "Headquarters")
                     : (facility.kind == .branch
                        ? String(localized: "Branch · level \(facility.level)")
                        : String(localized: "Warehouse · level \(facility.level)")))
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(operational
                     ? (facility.kind == .branch
                        ? String(localized: "Contracts can be signed from this city")
                        : String(localized: "Freight can be stored and consolidated here"))
                     : String(localized: "Under construction — \(Format.duration(minutes: state.clock.minutes(until: facility.operationalAt))) left"))
                    .font(.gg(11, .bold))
                    .foregroundStyle(operational ? Theme.textSecondary : accent)
            }
            Spacer()
        }
        .padding(12)
        .surfacePanel(cornerRadius: 18)
    }

    private func buildOfferRow(kind: FacilityKind, quote: FacilityQuote, cash: Money) -> some View {
        let affordable = cash >= quote.cost
        return Button {
            buildError = session.perform(.buildFacility(kind: kind, cityID: activeCityID))
        } label: {
            HStack(spacing: 11) {
                Image(systemName: kind == .branch ? "building.2" : "shippingbox")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(affordable ? accent : Theme.textTertiary)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind == .branch
                         ? String(localized: "Build a branch")
                         : String(localized: "Build a warehouse"))
                        .font(.gg(12.5, .heavy))
                        .foregroundStyle(affordable ? Theme.textPrimary : Theme.textTertiary)
                    // Why it is worth the money, then what it costs here.
                    Text(kind == .branch
                         ? String(localized: "Unlocks contract lanes from this city")
                         : String(localized: "Store, consolidate and redistribute freight"))
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

    private var buildErrorMessage: LocalizedStringKey {
        switch buildError {
        case .insufficientFunds(let required): "You need \(Format.money(required)) to build here."
        case .facilityAlreadyExists: "You already have that building in this city."
        default: "That building cannot be started right now."
        }
    }

    private var vehiclesSection: some View {
        let vehicles = session.state.map { state in
            state.vehicles.filter { physicalCityID(for: $0, state: state) == activeCityID }
        } ?? []
        return VStack(alignment: .leading, spacing: 9) {
            SectionLabel(String(localized: "Vehicles in city"))
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
        let type = session.catalog.vehicleType(vehicle.typeID)
        let code = Format.vehicleCode(typeName: type?.name ?? "VEH", id: vehicle.id)
        let status = vehicleStatus(vehicle)
        return HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text("\(code) · \(status.label)")
                .font(.gg(12, .heavy))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(red: 140 / 255, green: 170 / 255, blue: 215 / 255).opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private func contractAddressLine(for offer: JobOffer) -> String? {
        guard offer.source == .contract,
              let originFirmID = offer.originFirmID,
              let destinationFirmID = offer.destinationFirmID,
              let origin = session.catalog.firm(originFirmID)?.name,
              let destination = session.catalog.firm(destinationFirmID)?.name else { return nil }
        return "\(origin) → \(destination)"
    }

    private func physicalCityID(for vehicle: Vehicle, state: GameState) -> CityID? {
        if let run = state.routeRun(for: vehicle.id) {
            switch run.phase {
            case .traveling:
                return nil
            case .servicing, .waiting:
                return vehicle.cityID
            }
        }
        if let job = state.activeJob(for: vehicle.id) {
            switch job.phase {
            case .deadheading, .enRoute:
                return nil
            case .loading:
                return job.offer.origin
            case .unloading:
                return job.offer.destination
            }
        }
        return vehicle.cityID
    }

    private func vehicleStatus(_ vehicle: Vehicle) -> (label: String, color: Color) {
        guard let state = session.state else {
            return (String(localized: "idle"), Theme.textTertiary)
        }
        if let run = state.routeRun(for: vehicle.id) {
            switch run.phase {
            case .traveling:
                return (String(localized: "on route"), Theme.mint)
            case .servicing:
                guard let route = state.route(run.routeID),
                      route.stops.indices.contains(run.stopIndex) else {
                    return (String(localized: "servicing"), Theme.mint)
                }
                switch route.stops[run.stopIndex].task {
                case .pickupShipment, .pickupContract, .loadFromWarehouse:
                    return (String(localized: "loading"), Theme.mint)
                case .deliverShipment, .deliverContract, .deliverAll:
                    return (String(localized: "unloading"), Theme.mint)
                case .dropToWarehouse:
                    return (String(localized: "storing"), Theme.sky)
                case .travel:
                    return (String(localized: "servicing"), Theme.mint)
                }
            case .waiting:
                return (String(localized: "waiting"), Theme.sky)
            }
        }
        if let job = state.activeJob(for: vehicle.id) {
            switch job.phase {
            case .deadheading:
                return (String(localized: "to pickup"), Theme.mint)
            case .loading:
                return (String(localized: "loading"), Theme.mint)
            case .enRoute:
                return (String(localized: "en route"), Theme.mint)
            case .unloading:
                return (String(localized: "unloading"), Theme.mint)
            }
        }
        if state.route(of: vehicle.id) != nil {
            return (String(localized: "standby"), Theme.sky)
        }
        return (String(localized: "idle"), Theme.textTertiary)
    }
}
