//
//  JobsView.swift
//  Goods&Glory
//
//  Operations tab: Active / Contracts / Market. One level of navigation —
//  contracts are the steadiest income source and must not be buried.
//

import SwiftUI

/// One level of navigation, three honest modes. Contracts used to sit three
/// taps deep (Jobs → Market → Contract) which made the game's steadiest income
/// source the hardest thing to find.
private enum JobsMode: CaseIterable {
    case active, contracts, market
    var title: String {
        switch self {
        case .active: return "Active"
        case .contracts: return "Contracts"
        case .market: return "Market"
        }
    }
}

private enum ActiveJobFilter: String, CaseIterable {
    case all = "All"
    case enRoute = "En route"
    case loading = "Loading"
    case pickup = "Pickup"
}

struct JobsView: View {
    @Environment(GameSession.self) private var session
    @State private var mode: JobsMode = .active
    @State private var activeFilter: ActiveJobFilter = .all

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Operations", trailing: "Reputation —/100")
                    .padding(.horizontal, 14)

                jobsModePicker
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch mode {
                        case .active: activeContent
                        case .contracts: ContractMarketList(accent: accent)
                        case .market: marketContent
                        }
                        Color.clear.frame(height: Layout.tabBarClearance)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationDestination(for: JobID.self) { offerID in
                OfferDetailView(offerID: offerID)
            }
        }
        .tint(accent)
    }

    private var jobsModePicker: some View {
        HStack(spacing: 5) {
            ForEach(JobsMode.allCases, id: \.self) { item in
                let isActive = mode == item
                Button { mode = item } label: {
                    Text(item.title)
                        .font(.gg(13, .heavy))
                        .foregroundStyle(isActive ? Theme.onBrand : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(isActive ? accent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    @ViewBuilder private var activeContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ActiveJobFilter.allCases, id: \.self) { filter in
                    let selected = activeFilter == filter
                    Button { activeFilter = filter } label: {
                        Text(filter.rawValue)
                            .font(.gg(11.5, .heavy))
                            .foregroundStyle(selected ? Theme.onBrand : Theme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(selected ? accent : Theme.surface))
                            .overlay(Capsule().stroke(selected ? accent : Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        let jobs = filteredActiveJobs
        let runs = filteredRouteRuns
        if jobs.isEmpty && runs.isEmpty {
            Text("No active jobs match this filter.")
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .surfacePanel(cornerRadius: 16)
        } else {
            ForEach(runs) { run in
                CompactRouteRunRow(run: run, accent: accent)
            }
            ForEach(jobs) { job in
                CompactActiveJobRow(job: job, accent: accent)
            }
        }
    }

    /// Spot freight only. Contract lanes have their own mode now.
    @ViewBuilder private var marketContent: some View {
        Text("One-off hauls — fill empty legs, grab opportunities")
            .font(.gg(11, .heavy))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)

        let offers = (session.state?.offers ?? [])
            .filter { $0.source == .spot }
            .sorted { $0.expiresAt < $1.expiresAt }
        if offers.isEmpty {
            Text("No open offers. New freight appears as time passes.")
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .surfacePanel()
        } else {
            ForEach(offers) { offer in
                NavigationLink(value: offer.id) {
                    OfferRow(offer: offer)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredActiveJobs: [ActiveJob] {
        let jobs = (session.state?.activeJobs ?? []).sorted { $0.phaseEndsAt < $1.phaseEndsAt }
        switch activeFilter {
        case .all: return jobs
        case .enRoute: return jobs.filter { $0.phase == .enRoute || $0.phase == .deadheading }
        case .loading: return jobs.filter { $0.phase == .loading || $0.phase == .unloading }
        case .pickup: return jobs.filter { $0.phase == .loading }
        }
    }

    private var filteredRouteRuns: [RouteRun] {
        guard let state = session.state else { return [] }
        let runs = state.routeRuns.sorted { $0.phaseEndsAt < $1.phaseEndsAt }
        switch activeFilter {
        case .all:
            return runs
        case .enRoute:
            return runs.filter { $0.phase == .traveling }
        case .loading:
            return runs.filter { $0.phase == .servicing }
        case .pickup:
            return runs.filter { run in
                guard run.phase == .servicing,
                      let route = state.route(run.routeID),
                      route.stops.indices.contains(run.stopIndex) else { return false }
                switch route.stops[run.stopIndex].task {
                case .pickupShipment, .pickupContract, .loadFromWarehouse: return true
                case .travel, .deliverShipment, .deliverContract,
                     .deliverAll, .dropToWarehouse: return false
                }
            }
        }
    }
}

private struct CompactActiveJobRow: View {
    @Environment(GameSession.self) private var session
    let job: ActiveJob
    var accent: Color

    private var vehicle: Vehicle? { session.state?.vehicle(job.vehicleID) }
    private var vehicleType: VehicleTypeDefinition? {
        vehicle.flatMap { session.catalog.vehicleType($0.typeID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(statusColor.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: session.catalog.product(job.offer.productID)?.symbol
                          ?? "shippingbox.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cityName(job.offer.origin)) → \(cityName(job.offer.destination))")
                        .font(.gg(13.5, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let vehicle, let vehicleType {
                        Text(Format.vehicleCode(typeName: vehicleType.name, id: vehicle.id))
                            .font(.gg(10.5, .bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(statusLabel)
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(statusColor)
                    if let clock = session.state?.clock {
                        Text("\(Format.shortDuration(minutes: max(0, clock.minutes(until: job.phaseEndsAt)))) left")
                            .font(.gg(10.5, .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                }
            }

            ThemeProgressBar(value: progress, tint: barColor, height: 5)

            HStack(spacing: 7) {
                if job.offer.source == .contract {
                    TagPill(text: String(localized: "Contract"), color: Theme.brand)
                } else {
                    TagPill(text: String(localized: "Spot"), color: Theme.textSecondary)
                }
                StatChip(symbol: "scalemass.fill", text: Format.mass(kg: job.offer.load.massKg))
                StatChip(symbol: "arrow.left.and.right", text: Format.distance(km: job.offer.distanceKm))
                Spacer(minLength: 0)
                Text(Format.money(job.offer.payout))
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.mint)
                    .monospacedDigit()
            }
        }
        .padding(13)
        .surfacePanel(cornerRadius: 18)
    }

    private var progress: Double {
        guard let clock = session.state?.clock else { return 0 }
        let total = max(1, job.phaseStartedAt.minutes(until: job.phaseEndsAt))
        let elapsed = job.phaseStartedAt.minutes(until: clock)
        return min(1, max(0, Double(elapsed) / Double(total)))
    }

    private var statusLabel: String {
        switch job.phase {
        case .deadheading: return "To pickup"
        case .loading: return "Loading"
        case .enRoute: return "En route"
        case .unloading: return "Unload"
        }
    }

    private var statusColor: Color {
        switch job.phase {
        case .enRoute: return Theme.mint
        case .loading, .unloading: return accent
        case .deadheading: return Theme.textSecondary
        }
    }

    private var barColor: Color {
        job.phase == .enRoute ? Theme.mint : accent
    }

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

private struct CompactRouteRunRow: View {
    @Environment(GameSession.self) private var session
    let run: RouteRun
    var accent: Color

    private var route: Route? { session.state?.route(run.routeID) }

    private var stop: RouteStop? {
        guard let route, route.stops.indices.contains(run.stopIndex) else { return nil }
        return route.stops[run.stopIndex]
    }

    private var vehicle: Vehicle? { session.state?.vehicle(run.vehicleID) }
    private var vehicleType: VehicleTypeDefinition? {
        vehicle.flatMap { session.catalog.vehicleType($0.typeID) }
    }

    /// What this vehicle is actually carrying right now.
    private var cargo: [Shipment] {
        session.state?.shipments(onBoard: run.vehicleID) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            legLine
            ThemeProgressBar(value: progress, tint: statusColor, height: 5)
            cargoStrip
            footer
        }
        .padding(13)
        .surfacePanel(cornerRadius: 18)
    }

    // MARK: Header — who, on what route

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: vehicleType?.symbol ?? "truck.box.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(route?.name ?? String(localized: "Route \(run.routeID.rawValue)"))
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let vehicle, let vehicleType {
                    Text(Format.vehicleCode(typeName: vehicleType.name, id: vehicle.id))
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(statusLabel)
                    .font(.gg(11.5, .heavy))
                    .foregroundStyle(statusColor)
                if let eta {
                    Text(eta)
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: Leg — where it is going, and how far round the lap

    private var legLine: some View {
        HStack(spacing: 6) {
            Text(cityName(run.legOriginCityID))
                .font(.gg(11.5, .heavy))
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
            Text(stop.map { cityName($0.cityID) } ?? "—")
                .font(.gg(11.5, .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 4)
            if let route, !route.stops.isEmpty {
                Text("\(run.stopIndex + 1)/\(route.stops.count)")
                    .font(.gg(10.5, .heavy))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Cargo — the thing the old row never showed

    @ViewBuilder private var cargoStrip: some View {
        if cargo.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 10, weight: .bold))
                Text(run.phase == .waiting ? "Waiting for cargo" : "Running empty")
                    .font(.gg(10.5, .heavy))
            }
            .foregroundStyle(run.phase == .waiting ? Theme.sky : Theme.coral)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                // Load against capacity: the number that decides whether this
                // lap was worth driving.
                if let vehicleType {
                    let load = session.state?.cargoLoad(of: run.vehicleID)
                        ?? LoadSize(massKg: 0, volumeM3: 0)
                    let fill = vehicleType.capacity.massKg > 0
                        ? Double(load.massKg) / Double(vehicleType.capacity.massKg) : 0
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(fillColor(fill))
                        Text("\(Format.mass(kg: load.massKg)) / \(Format.mass(kg: vehicleType.capacity.massKg))")
                            .font(.gg(10.5, .heavy))
                            .foregroundStyle(Theme.textSecondary)
                            .monospacedDigit()
                        Text("\(Int((fill * 100).rounded()))% full")
                            .font(.gg(10.5, .heavy))
                            .foregroundStyle(fillColor(fill))
                        Spacer(minLength: 0)
                    }
                }
                // Where the load is going, grouped so ten parcels are one line.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(cargoGroups, id: \.city) { group in
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 8, weight: .bold))
                                Text("\(cityName(group.city)) ×\(group.count)")
                                    .font(.gg(10, .heavy))
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Theme.surface))
                        }
                    }
                }
            }
        }
    }

    private var cargoGroups: [(city: CityID, count: Int)] {
        var counts: [CityID: Int] = [:]
        for shipment in cargo {
            counts[shipment.offer.destination, default: 0] += 1
        }
        return counts
            .map { (city: $0.key, count: $0.value) }
            .sorted { $0.city.rawValue < $1.city.rawValue }
    }

    private func fillColor(_ fill: Double) -> Color {
        if fill >= 0.7 { return Theme.mint }
        if fill >= 0.35 { return accent }
        return Theme.coral
    }

    // MARK: Footer — money earned by what is on board

    @ViewBuilder private var footer: some View {
        let pending = cargo.reduce(0) { $0 + $1.offer.payout }
        if pending > 0 {
            HStack(spacing: 4) {
                Text("On delivery")
                    .font(.gg(10.5, .bold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(Format.money(pending))
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.mint)
                    .monospacedDigit()
            }
        }
    }

    private var eta: String? {
        guard run.phase != .waiting, let clock = session.state?.clock else { return nil }
        let remaining = max(0, clock.minutes(until: run.phaseEndsAt))
        return String(localized: "\(Format.shortDuration(minutes: remaining)) left")
    }

    private var statusLabel: String {
        switch run.phase {
        case .traveling:
            return String(localized: "En route")
        case .servicing:
            return serviceLabel
        case .waiting:
            guard let stop,
                  case .pickupContract(let contractID) = stop.task,
                  session.state?.activeContract(contractID) != nil else {
                return String(localized: "Waiting")
            }
            return String(localized: "Waiting for cargo")
        }
    }

    private var serviceLabel: String {
        guard let stop else { return String(localized: "Servicing") }
        switch stop.task {
        case .pickupShipment, .pickupContract: return String(localized: "Loading")
        case .loadFromWarehouse: return String(localized: "Loading from warehouse")
        case .deliverShipment, .deliverContract, .deliverAll: return String(localized: "Unloading")
        case .dropToWarehouse: return String(localized: "Storing")
        case .travel: return String(localized: "Servicing")
        }
    }

    private var progress: Double {
        guard run.phase != .waiting, let clock = session.state?.clock else { return 0 }
        let total = max(1, run.phaseStartedAt.minutes(until: run.phaseEndsAt))
        let elapsed = run.phaseStartedAt.minutes(until: clock)
        return min(1, max(0, Double(elapsed) / Double(total)))
    }

    private var statusColor: Color {
        switch run.phase {
        case .traveling: return Theme.mint
        case .servicing: return accent
        case .waiting: return Theme.sky
        }
    }

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

// MARK: - Shared rows

private func firmAddressLine(
    catalog: GameCatalog,
    originFirmID: FirmID?,
    destinationFirmID: FirmID?
) -> String? {
    guard let originFirmID,
          let destinationFirmID,
          let origin = catalog.firm(originFirmID)?.name,
          let destination = catalog.firm(destinationFirmID)?.name else { return nil }
    return "\(origin) → \(destination)"
}

struct OfferRow: View {
    @Environment(GameSession.self) private var session
    let offer: JobOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(cityName(offer.origin)) → \(cityName(offer.destination))")
                    .font(.gg(15.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if offer.source == .contract {
                    TagPill(text: String(localized: "Contract"), color: Theme.brand)
                }
                TagPill(text: urgencyLabel(offer.urgency), color: urgencyColor(offer.urgency))
                if let clock = session.state?.clock {
                    TagPill(text: expiryTag(minutes: clock.minutes(until: offer.expiresAt)),
                            color: expiryColor(minutes: clock.minutes(until: offer.expiresAt)))
                }
            }
            if let address = firmAddressLine(
                catalog: session.catalog,
                originFirmID: offer.originFirmID,
                destinationFirmID: offer.destinationFirmID
            ) {
                Text(address)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                if let product = session.catalog.product(offer.productID) {
                    Label(String(localized: String.LocalizationValue(product.name)), systemImage: product.symbol)
                }
                Text(Format.mass(kg: offer.load.massKg))
                Text(Format.distance(km: offer.distanceKm))
            }
            .font(.gg(11.5, .bold))
            .foregroundStyle(Theme.textSecondary)
            HStack {
                Text(Format.money(offer.payout))
                    .font(.gg(17, .heavy))
                    .foregroundStyle(Theme.mint)
                    .monospacedDigit()
                Spacer()
                Text("Assign")
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.onBrand)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.brand))
            }
        }
        .padding(16)
        .surfacePanel()
    }

    private func urgencyLabel(_ urgency: JobUrgency) -> String {
        switch urgency {
        case .economy: return String(localized: "Economy")
        case .normal: return String(localized: "Standard")
        case .urgent: return String(localized: "Urgent")
        }
    }

    private func urgencyColor(_ urgency: JobUrgency) -> Color {
        switch urgency {
        case .economy: return Theme.textSecondary
        case .normal: return Theme.sky
        case .urgent: return Theme.coral
        }
    }

    private func expiryTag(minutes: Int) -> String {
        minutes <= 240 ? String(localized: "Expiring") : String(localized: "Open")
    }
    private func expiryColor(minutes: Int) -> Color {
        minutes <= 240 ? Theme.coral : Theme.textSecondary
    }
    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

struct VehicleRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle

    var body: some View {
        HStack {
            if let vehicleType = session.catalog.vehicleType(vehicle.typeID) {
                Label(String(localized: String.LocalizationValue(vehicleType.name)), systemImage: vehicleType.symbol)
                    .font(.gg(13.5, .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if vehicle.isAvailable {
                Text(session.catalog.city(vehicle.cityID)?.name ?? "")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("On the job")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.mint)
            }
        }
    }
}

struct ActiveJobRow: View {
    let job: ActiveJob
    var body: some View {
        CompactActiveJobRow(job: job, accent: Theme.brand)
    }
}

// MARK: - Contracts

private struct ContractMarketList: View {
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

private struct ContractOfferRow: View {
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

    // MARK: The one number that decides it

    @ViewBuilder private var headline: some View {
        if let brief = session.brief(for: offer) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.money(brief.profitPerDay))
                    .font(.gg(24, .heavy))
                    .foregroundStyle(brief.isViable ? Theme.mint : Theme.coral)
                    .monospacedDigit()
                Text("/ day")
                    .font(.gg(11.5, .heavy))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if !brief.isViable {
                    Label("Loses money", systemImage: "exclamationmark.triangle.fill")
                        .font(.gg(10.5, .heavy))
                        .foregroundStyle(Theme.coral)
                        .labelStyle(.titleAndIcon)
                }
            }
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
                    String(localized: "Fleet time used"),
                    "\(Int((brief.utilization * 100).rounded()))%"
                )
            }
            if let address = firmAddressLine(
                catalog: session.catalog,
                originFirmID: offer.originFirmID,
                destinationFirmID: offer.destinationFirmID
            ) {
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
        let origin = cityName(offer.origin)
        let drops = offer.destinations.map { cityName($0.cityID) }
        guard drops.count > 1 else { return "\(origin) → \(drops.first ?? "—")" }
        return "\(origin) → \(drops[0]) +\(drops.count - 1)"
    }

    private var archetypeLabel: String {
        switch offer.archetype {
        case .laneRecurring: String(localized: "Lane")
        case .bulkPeriodic: String(localized: "Bulk")
        case .evergreen: String(localized: "Ongoing")
        case .multiDrop: String(localized: "Multi-drop")
        }
    }

    private var archetypeColor: Color {
        switch offer.archetype {
        case .laneRecurring: Theme.mint
        case .bulkPeriodic: Theme.coral
        case .evergreen: Theme.sky
        case .multiDrop: Theme.violet
        }
    }

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

private struct ActiveContractRow: View {
    @Environment(GameSession.self) private var session
    let contract: ActiveContract
    var accent: Color
    @State private var showsAssignSheet = false
    @State private var assignError: CommandError?

    private var route: Route? { session.state?.route(forContract: contract.id) }

    private var assignedVehicles: [Vehicle] {
        guard let route, let state = session.state else { return [] }
        return route.vehicleIDs.compactMap { state.vehicle($0) }
    }

    /// Shipments posted and still waiting for a vehicle.
    private var pendingShipments: Int {
        (session.state?.offers ?? []).count { $0.source == .contract && $0.contractID == contract.id }
    }

    private var laneTitle: String {
        let origin = cityName(contract.origin)
        let drops = contract.destinations.map { cityName($0.cityID) }
        guard drops.count > 1 else { return "\(origin) → \(drops.first ?? "—")" }
        return "\(origin) → \(drops[0]) +\(drops.count - 1)"
    }

    private var archetypeLabel: String {
        switch contract.archetype {
        case .laneRecurring: String(localized: "Lane")
        case .bulkPeriodic: String(localized: "Bulk")
        case .evergreen: String(localized: "Ongoing")
        case .multiDrop: String(localized: "Multi-drop")
        }
    }

    private var archetypeColor: Color {
        switch contract.archetype {
        case .laneRecurring: Theme.mint
        case .bulkPeriodic: Theme.coral
        case .evergreen: Theme.sky
        case .multiDrop: accent
        }
    }

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
                            assignError = session.perform(
                                .unassignVehicleFromContract(contractID: contract.id, vehicleID: vehicle.id)
                            )
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

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

/// One-tap vehicle assignment for a signed contract. Lists every vehicle with
/// its fit and projected per-shipment cycle profit on this lane.
private struct ContractAssignSheet: View {
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
                    Text("The vehicle loops this lane automatically: pick up at \(cityName(contract.origin)), deliver to \(cityName(contract.destination)), return empty, wait for the next shipment.")
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
                    Text("Joins the lane after finishing its current job.")
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

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

// MARK: - Offer detail & acceptance

struct OfferDetailView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let offerID: JobID
    /// When shown under the floating game tab bar, leave scroll clearance.
    var clearsFloatingTabBar: Bool = true
    @State private var selectedVehicleID: VehicleID?
    @State private var commandError: CommandError?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }
    private var offer: JobOffer? { session.state?.offers.first { $0.id == offerID } }

    var body: some View {
        ScrollView {
            if let offer {
                VStack(alignment: .leading, spacing: 14) {
                    offerDetails(offer)
                    vehiclePicker(offer)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            } else {
                ContentUnavailableView(
                    "Offer No Longer Available",
                    systemImage: "clock.badge.xmark",
                    description: Text("This offer expired or was taken.")
                )
                .padding(.top, 80)
            }
        }
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .navigationTitle("Spot Job")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if offer != nil { acceptButton }
        }
        .alert(
            "Could Not Assign Job",
            isPresented: Binding(get: { commandError != nil }, set: { if !$0 { commandError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .tint(accent)
    }

    @ViewBuilder
    private func offerDetails(_ offer: JobOffer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(cityName(offer.origin)) → \(cityName(offer.destination))")
                .font(.gg(22, .heavy))
                .foregroundStyle(Theme.textPrimary)
            if let address = firmAddressLine(
                catalog: session.catalog,
                originFirmID: offer.originFirmID,
                destinationFirmID: offer.destinationFirmID
            ) {
                Text(address)
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let product = session.catalog.product(offer.productID) {
                    DetailTile(label: "Cargo", value: String(localized: String.LocalizationValue(product.name)), symbol: product.symbol)
                }
                DetailTile(label: "Load", value: "\(Format.mass(kg: offer.load.massKg)) · \(Format.volume(m3: offer.load.volumeM3))")
                DetailTile(label: "Distance", value: Format.distance(km: offer.distanceKm))
                DetailTile(label: "Payout", value: Format.money(offer.payout), tint: Theme.mint)
                DetailTile(label: "Rate", value: urgencyDetailLabel(offer.urgency))
                DetailTile(
                    label: "Source",
                    value: offer.source == .contract
                        ? String(localized: "Contract")
                        : String(localized: "Spot")
                )
                if let clock = session.state?.clock {
                    DetailTile(label: "Expires in", value: Format.duration(minutes: clock.minutes(until: offer.expiresAt)))
                }
            }
        }
        .padding(16)
        .surfacePanel(cornerRadius: 22)
    }

    @ViewBuilder
    private func vehiclePicker(_ offer: JobOffer) -> some View {
        let idleVehicles: [Vehicle] = {
            guard let state = session.state else { return [] }
            let busy = state.busyVehicleIDs()
            return state.vehicles.filter { !busy.contains($0.id) }
        }()
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Assign Vehicle")
            if idleVehicles.isEmpty {
                Text("No idle vehicles. Wait for a delivery to finish or buy a new vehicle.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surfacePanel()
            }
            ForEach(idleVehicles) { vehicle in
                let estimate = session.estimate(offer: offer, vehicle: vehicle)
                Button {
                    selectedVehicleID = vehicle.id
                } label: {
                    VehicleEstimateRow(vehicle: vehicle, estimate: estimate, isSelected: selectedVehicleID == vehicle.id, accent: accent)
                }
                .buttonStyle(.plain)
                .disabled(estimate == nil)
            }
        }
    }

    private var acceptButton: some View {
        Button {
            guard let selectedVehicleID else { return }
            if let error = session.perform(.acceptJob(offerID: offerID, vehicleID: selectedVehicleID)) {
                commandError = error
            } else {
                dismiss()
            }
        } label: {
            Text("Accept Job")
        }
        .buttonStyle(PrimaryButtonStyle(tint: accent))
        .disabled(selectedVehicleID == nil)
        .opacity(selectedVehicleID == nil ? 0.45 : 1)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, clearsFloatingTabBar ? Layout.tabBarClearance : 16)
        .background(Theme.backgroundBottom.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }

    private var errorMessage: LocalizedStringKey {
        switch commandError {
        case .insufficientFunds: "Not enough cash."
        case .vehicleBusy: "That vehicle is already on a job."
        case .offerExpired: "The offer expired."
        case .loadExceedsCapacity: "The load does not fit this vehicle."
        case .noRoute: "No road connection to the pickup city."
        case .noVehicleAssigned, .incompleteRouteTasks,
             .vehicleAlreadyAssigned, .routeIsRunning: "That vehicle is not available."
        case .branchRequired: "You need a branch in this city to take contracts here."
        case .warehouseRequired: "This city has no warehouse."
        case .facilityAlreadyExists: "You already have that building here."
        case .facilityNotAvailable: "That building is busy or already at its top level."
        case .warehouseNotEmpty: "Empty the warehouse before tearing it down."
        case .cannotDemolishHeadquarters: "Headquarters cannot be demolished."
        case .unknownReference, nil: "The offer or vehicle is no longer available."
        }
    }

    private func urgencyDetailLabel(_ urgency: JobUrgency) -> String {
        switch urgency {
        case .economy: return String(localized: "Economy")
        case .normal: return String(localized: "Standard")
        case .urgent: return String(localized: "Urgent")
        }
    }

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

private struct DetailTile: View {
    let label: String
    let value: String
    var symbol: String? = nil
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(tint) }
                Text(value).font(.gg(14, .heavy)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
    }
}

private struct VehicleEstimateRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    let estimate: SimulationEngine.JobEstimate?
    let isSelected: Bool
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let vehicleType = session.catalog.vehicleType(vehicle.typeID) {
                    Label(String(localized: String.LocalizationValue(vehicleType.name)), systemImage: vehicleType.symbol)
                        .font(.gg(14, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("· \(session.catalog.city(vehicle.cityID)?.name ?? "")")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let route = session.state?.route(of: vehicle.id) {
                    TagPill(
                        text: route.contractID == nil
                            ? String(localized: "Route")
                            : String(localized: "Contract"),
                        color: route.contractID == nil ? Theme.sky : Theme.warning
                    )
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                }
            }
            if let estimate {
                HStack(spacing: 12) {
                    Text("Profit \(Format.money(estimate.estimatedProfit))")
                        .foregroundStyle(estimate.estimatedProfit >= 0 ? Theme.mint : Theme.coral)
                    Text(Format.duration(minutes: estimate.totalMinutes))
                        .foregroundStyle(Theme.textSecondary)
                    if estimate.deadheadKm > 0 {
                        Text("\(Format.distance(km: estimate.deadheadKm)) empty")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(.gg(11.5, .bold))
            } else {
                Text("Load does not fit this vehicle.")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(15)
        .surfacePanel(selected: isSelected, accent: accent)
        .contentShape(Rectangle())
    }
}
