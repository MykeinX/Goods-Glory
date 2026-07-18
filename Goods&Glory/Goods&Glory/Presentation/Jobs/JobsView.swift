//
//  JobsView.swift
//  Goods&Glory
//
//  Jobs market (design 1e): Spot / Contract / Tender segments. Spot is the live
//  freight market backed by the simulation; Contract and Tender are visual
//  shells for future long-term deals. Shared rows are also used by the map's
//  city sheet.
//

import SwiftUI

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

struct JobsView: View {
    @Environment(GameSession.self) private var session
    @State private var segment: JobSegment = .spot

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "Jobs", trailing: "Reputation —/100")

                    SegmentPicker(segment: $segment, accent: accent)

                    Text(segment.hint)
                        .font(.gg(12, .bold))
                        .foregroundStyle(Theme.textTertiary)

                    switch segment {
                    case .spot: spotContent
                    case .contract: ShellDealList(kind: .contract, accent: accent)
                    case .tender: ShellDealList(kind: .tender, accent: accent)
                    }

                    Color.clear.frame(height: Layout.tabBarClearance)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationDestination(for: JobID.self) { offerID in
                OfferDetailView(offerID: offerID)
            }
        }
        .tint(accent)
    }

    @ViewBuilder private var spotContent: some View {
        let activeJobs = (session.state?.activeJobs ?? []).sorted { $0.phaseEndsAt < $1.phaseEndsAt }
        if !activeJobs.isEmpty {
            SectionLabel("Active Jobs")
            ForEach(activeJobs) { job in
                ActiveJobRow(job: job)
            }
        }

        SectionLabel("Open Offers")
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
                Button {
                    segment = seg
                } label: {
                    Text(seg.title)
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
}

// MARK: - Shared rows

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
                if let clock = session.state?.clock {
                    TagPill(text: expiryTag(minutes: clock.minutes(until: offer.expiresAt)),
                            color: expiryColor(minutes: clock.minutes(until: offer.expiresAt)))
                }
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

    private func expiryTag(minutes: Int) -> String {
        minutes <= 240 ? "Urgent" : "Spot"
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
    @Environment(GameSession.self) private var session
    let job: ActiveJob

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(cityName(job.offer.origin)) → \(cityName(job.offer.destination))")
                    .font(.gg(15, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(Format.money(job.offer.payout))
                    .font(.gg(13.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            HStack {
                Label(phaseTitle, systemImage: phaseSymbol)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.brand)
                Spacer()
                if let clock = session.state?.clock {
                    Text("Next: \(Format.duration(minutes: max(0, clock.minutes(until: job.phaseEndsAt))))")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(16)
        .surfacePanel()
    }

    private var phaseTitle: LocalizedStringKey {
        switch job.phase {
        case .deadheading: "Driving to pickup"
        case .loading: "Loading"
        case .enRoute: "En route"
        case .unloading: "Unloading"
        }
    }
    private var phaseSymbol: String {
        switch job.phase {
        case .deadheading: "arrow.uturn.right"
        case .loading: "tray.and.arrow.down"
        case .enRoute: "truck.box"
        case .unloading: "tray.and.arrow.up"
        }
    }
    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

// MARK: - Contract / Tender shells

private struct ShellDealList: View {
    enum Kind { case contract, tender }
    let kind: Kind
    var accent: Color

    private struct Deal { let title: String; let sub1: String; let sub2: String; let pay: String; let tag: String; let color: Color }

    private var deals: [Deal] {
        switch kind {
        case .contract:
            return [
                .init(title: "Regional Furniture Co.", sub1: "Weekly 60–90 t lane", sub2: "90 days • min 94% on-time • penalties", pay: "$182 / t", tag: "Contract", color: Theme.brand),
                .init(title: "Coastal Foods", sub1: "Weekly 30 t • cold chain", sub2: "60 days • reefer required • min 96%", pay: "$310 / t", tag: "Cold chain", color: Theme.sky)
            ]
        case .tender:
            return [
                .init(title: "TechNova Distribution", sub1: "5 regions • 12 cities • 6 months", sub2: "Closes in 3 days • reputation 60+ • 4 rivals bidding", pay: "≈ $420,000", tag: "Tender", color: Theme.violet),
                .init(title: "Continental Automotive", sub1: "Parts network • hub-based", sub2: "Closes in 9 days • intermodal favored", pay: "≈ $260,000", tag: "Tender", color: Theme.violet)
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(accent)
                Text("Preview — these deal types are coming in a later update.")
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
                    Color.clear.frame(height: 90)
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
            "Could Not Accept Job",
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
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let product = session.catalog.product(offer.productID) {
                    DetailTile(label: "Cargo", value: String(localized: String.LocalizationValue(product.name)), symbol: product.symbol)
                }
                DetailTile(label: "Load", value: "\(Format.mass(kg: offer.load.massKg)) · \(Format.volume(m3: offer.load.volumeM3))")
                DetailTile(label: "Distance", value: Format.distance(km: offer.distanceKm))
                DetailTile(label: "Payout", value: Format.money(offer.payout), tint: Theme.mint)
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
        let idleVehicles = (session.state?.vehicles ?? []).filter(\.isAvailable)
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
        .padding(.vertical, 12)
        .background(Theme.backgroundBottom.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }

    private var errorMessage: LocalizedStringKey {
        switch commandError {
        case .insufficientFunds: "Not enough cash."
        case .vehicleBusy: "That vehicle is already on a job."
        case .offerExpired: "The offer expired."
        case .loadExceedsCapacity: "The load does not fit this vehicle."
        case .noRoute: "No road connection to the pickup city."
        case .unknownReference, nil: "The offer or vehicle is no longer available."
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
