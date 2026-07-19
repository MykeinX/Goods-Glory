//
//  JobsView.swift
//  Goods&Glory
//
//  Jobs tab (design 3a): Active / Market mode. Active uses compact progress
//  rows with filters; Market keeps Spot / Contract / Tender.
//

import SwiftUI

private enum JobsMode: CaseIterable {
    case active, market
    var title: String {
        switch self {
        case .active: return "Active"
        case .market: return "Market"
        }
    }
}

private enum JobSegment: Int, CaseIterable {
    case spot, contract, tender
    var title: String {
        switch self {
        case .spot: return "Spot"
        case .contract: return "Contract"
        case .tender: return "Tender"
        }
    }
    var hint: String {
        switch self {
        case .spot: return "One-off hauls — fill empty legs, grab opportunities"
        case .contract: return "Steady income — reserve capacity, keep your SLA"
        case .tender: return "Big plays — compete with reputation and scale"
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
    @State private var segment: JobSegment = .spot
    @State private var activeFilter: ActiveJobFilter = .all

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Jobs", trailing: "Reputation —/100")
                    .padding(.horizontal, 14)

                jobsModePicker
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch mode {
                        case .active: activeContent
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

    @ViewBuilder private var marketContent: some View {
        SegmentPicker(segment: $segment, accent: accent)
        Text(segment.hint)
            .font(.gg(11, .heavy))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)

        switch segment {
        case .spot:
            let offers = (session.state?.offers ?? []).sorted { $0.expiresAt < $1.expiresAt }
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
        case .contract: ContractMarketList(accent: accent)
        case .tender: ShellDealList(kind: .tender, accent: accent)
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
                case .pickupShipment, .pickupContract: return true
                case .travel, .deliverShipment, .deliverContract: return false
                }
            }
        }
    }
}

// MARK: - Segment picker

private struct SegmentPicker: View {
    @Binding var segment: JobSegment
    var accent: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(JobSegment.allCases, id: \.self) { seg in
                let isActive = segment == seg
                Button { segment = seg } label: {
                    Text(seg.title)
                        .font(.gg(12.5, .heavy))
                        .foregroundStyle(isActive ? Theme.onBrand : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Capsule().fill(isActive ? accent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

private struct CompactActiveJobRow: View {
    @Environment(GameSession.self) private var session
    let job: ActiveJob
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text("\(cityName(job.offer.origin)) → \(cityName(job.offer.destination))")
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if job.offer.source == .contract {
                    TagPill(text: String(localized: "Contract"), color: Theme.brand)
                } else {
                    TagPill(text: String(localized: "Spot"), color: Theme.textSecondary)
                }
                Text(statusLabel)
                    .font(.gg(11, .heavy))
                    .foregroundStyle(statusColor)
            }
            ThemeProgressBar(value: progress, tint: barColor, height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .surfacePanel(cornerRadius: 16)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route?.name ?? "Route \(run.routeID.rawValue)")
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(legLabel)
                        .font(.gg(11, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(statusLabel)
                    .font(.gg(11, .heavy))
                    .foregroundStyle(statusColor)
            }
            ThemeProgressBar(value: progress, tint: statusColor, height: 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .surfacePanel(cornerRadius: 16)
    }

    private var legLabel: String {
        guard let stop else { return String(localized: "Route unavailable") }
        return "\(cityName(run.legOriginCityID)) → \(cityName(stop.cityID))"
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
        case .deliverShipment, .deliverContract: return String(localized: "Unloading")
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
        case .waiting: return Theme.textSecondary
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

    private var active: [ActiveContract] {
        (session.state?.activeContracts ?? []).sorted { $0.endsAt < $1.endsAt }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(cityName(offer.origin)) → \(cityName(offer.destination))")
                    .font(.gg(15.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                TagPill(text: String(localized: "Contract"), color: Theme.brand)
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
                Text(Format.mass(kg: offer.shipmentMassKg))
                Text(Format.distance(km: offer.distanceKm))
                if let referenceType = session.catalog.vehicleType(offer.referenceVehicleTypeID) {
                    Label(String(localized: String.LocalizationValue(referenceType.name)), systemImage: referenceType.symbol)
                }
            }
            .font(.gg(11.5, .bold))
            .foregroundStyle(Theme.textSecondary)
            Text("\(Format.money(offer.payoutPerShipment)) / shipment · every \(Format.duration(minutes: offer.shipmentIntervalMinutes)) · \(session.catalog.economy.contractDurationDays) days")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textTertiary)
            if let estimate = session.estimate(contractOffer: offer) {
                Text("Round trip \(Format.distance(km: estimate.roundTripKm)) · est. profit \(Format.money(estimate.profitPerShipment)) / shipment")
                    .font(.gg(12, .bold))
                    .foregroundStyle(estimate.profitPerShipment >= 0 ? Theme.mint : Theme.coral)
            }
            HStack {
                Text(Format.money(offer.payoutPerShipment))
                    .font(.gg(17, .heavy))
                    .foregroundStyle(Theme.mint)
                    .monospacedDigit()
                Spacer()
                Button(action: onSign) {
                    Text("Sign")
                        .font(.gg(12.5, .heavy))
                        .foregroundStyle(Theme.onBrand)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Capsule().fill(accent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .surfacePanel()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(cityName(contract.origin)) → \(cityName(contract.destination))")
                    .font(.gg(14.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                TagPill(text: String(localized: "Active"), color: Theme.mint)
            }
            if let address = firmAddressLine(
                catalog: session.catalog,
                originFirmID: contract.originFirmID,
                destinationFirmID: contract.destinationFirmID
            ) {
                Text(address)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                if let product = session.catalog.product(contract.productID) {
                    Label(String(localized: String.LocalizationValue(product.name)), systemImage: product.symbol)
                }
                Text(Format.mass(kg: contract.shipmentMassKg))
                Text("\(Format.money(contract.payoutPerShipment)) / shipment")
            }
            .font(.gg(11.5, .bold))
            .foregroundStyle(Theme.textSecondary)

            if let clock = session.state?.clock {
                Text("Ends in \(Format.duration(minutes: clock.minutes(until: contract.endsAt))) · next shipment in \(Format.duration(minutes: max(0, clock.minutes(until: contract.nextShipmentAt))))")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text("\(contract.shipmentsCompleted) delivered · \(contract.shipmentsMissed) missed\(contract.penaltiesPaid > 0 ? " · \(Format.money(contract.penaltiesPaid)) compensation" : "")")
                .font(.gg(11.5, .bold))
                .foregroundStyle(contract.shipmentsMissed > 0 ? Theme.coral : Theme.textTertiary)

            // Vehicle assignment: the core of keeping the obligation covered.
            if assignedVehicles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.coral)
                    Text(pendingShipments > 0
                         ? "No vehicle assigned — \(pendingShipments) shipment(s) waiting. Missed deadlines cost compensation."
                         : "No vehicle assigned. Missed shipments cost compensation.")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.coral)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.coral.opacity(0.10)))
            } else {
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

// MARK: - Tender shell

private struct ShellDealList: View {
    enum Kind { case tender }
    let kind: Kind
    var accent: Color

    private struct Deal { let title: String; let sub1: String; let sub2: String; let pay: String; let tag: String; let color: Color }

    private var deals: [Deal] {
        [
            .init(title: "TechNova Distribution", sub1: "5 regions • 12 cities • 6 months", sub2: "Closes in 3 days • reputation 60+ • 4 rivals bidding", pay: "≈ $420,000", tag: "Tender", color: Theme.violet),
            .init(title: "Continental Automotive", sub1: "Parts network • hub-based", sub2: "Closes in 9 days • intermodal favored", pay: "≈ $260,000", tag: "Tender", color: Theme.violet)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(accent)
                Text("Preview — tenders are coming in a later update.")
                    .font(.gg(11.5, .bold)).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.08)))

            ForEach(Array(deals.enumerated()), id: \.offset) { _, deal in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(deal.title).font(.gg(15, .heavy)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        TagPill(text: deal.tag, color: deal.color)
                    }
                    Text(deal.sub1).font(.gg(12, .bold)).foregroundStyle(Theme.textSecondary)
                    Text(deal.sub2).font(.gg(11, .bold)).foregroundStyle(Theme.textTertiary)
                    HStack {
                        Text(deal.pay).font(.gg(16, .heavy)).foregroundStyle(Theme.mint)
                        Spacer()
                    }
                }
                .padding(16)
                .surfacePanel()
                .opacity(0.85)
            }
        }
    }
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
        let idleVehicles = session.state.map { state in
            state.vehicles.filter { state.isVehicleIdle($0.id) }
        } ?? []
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
