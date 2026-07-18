//
//  MapTabView.swift
//  Goods&Glory
//
//  In-game map tab (design 1b): a full-bleed night map with a floating status
//  overlay (identity, cash, clock, speed), a live event banner and a scrolling
//  strip of the fleet's running jobs. Tapping a city opens a contextual sheet.
//

import SwiftUI

private struct SelectedCity: Identifiable {
    let id: CityID
}

struct MapTabView: View {
    @Environment(GameSession.self) private var session
    @State private var selectedCityID: CityID?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        ZStack {
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
                    selectedCityID: $selectedCityID
                )
                .ignoresSafeArea()

                // Top gradient scrim so the overlay reads over the map.
                LinearGradient(colors: [Theme.backgroundTop, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 190)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MapStatusOverlay(accent: accent)
                    Spacer()
                    MapFleetStrip(accent: accent)
                }
            } else {
                Theme.backgroundTop.ignoresSafeArea()
            }
        }
        .sheet(item: selectionBinding) { selection in
            CityDetailSheet(cityID: selection.id)
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationBackground(Theme.backgroundBottom)
        }
    }

    private var selectionBinding: Binding<SelectedCity?> {
        Binding(
            get: { selectedCityID.map(SelectedCity.init(id:)) },
            set: { selectedCityID = $0?.id }
        )
    }
}

// MARK: - Top status overlay

private struct MapStatusOverlay: View {
    @Environment(GameSession.self) private var session
    var accent: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if let identity = session.state?.config.identity {
                    HStack(spacing: 8) {
                        Text(identity.name.prefix(1).uppercased())
                            .font(.gg(11, .heavy))
                            .foregroundStyle(Theme.onBrand)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent))
                        Text(identity.name)
                            .font(.gg(12.5, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .glassPill()
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text(Format.money(session.state?.cash ?? 0))
                        .font(.gg(15, .heavy))
                        .foregroundStyle(Theme.mint)
                        .monospacedDigit()
                }
                .glassPill()
            }

            HStack {
                if let clock = session.state?.clock {
                    Text(Format.gameTime(clock))
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .glassPill()
                }
                Spacer(minLength: 8)
                GameSpeedControl(accent: accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

/// The paused / 1× / 3× / 8× time control.
struct GameSpeedControl: View {
    @Environment(GameSession.self) private var session
    var accent: Color

    private struct Speed { let value: SimulationSpeed; let label: String; let symbol: String? }
    private let speeds: [Speed] = [
        .init(value: .paused, label: "", symbol: "pause.fill"),
        .init(value: .normal, label: "1×", symbol: nil),
        .init(value: .fast, label: "3×", symbol: nil),
        .init(value: .veryFast, label: "8×", symbol: nil)
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(speeds, id: \.value) { speed in
                let isActive = session.speed == speed.value
                Button {
                    session.speed = speed.value
                } label: {
                    Group {
                        if let symbol = speed.symbol {
                            Image(systemName: symbol).font(.system(size: 11, weight: .heavy))
                        } else {
                            Text(speed.label).font(.gg(12, .heavy))
                        }
                    }
                    .foregroundStyle(isActive ? Theme.onBrand : Theme.textSecondary)
                    .frame(minWidth: 34, minHeight: 30)
                    .background(Capsule().fill(isActive ? accent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surfaceGlass))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

private extension View {
    func glassPill() -> some View {
        self
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.surfaceGlass))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Bottom fleet strip (running jobs)

private struct MapFleetStrip: View {
    @Environment(GameSession.self) private var session
    var accent: Color

    var body: some View {
        VStack(spacing: 10) {
            let jobs = (session.state?.activeJobs ?? []).sorted { $0.phaseEndsAt < $1.phaseEndsAt }
            let idle = (session.state?.vehicles ?? []).filter(\.isAvailable)

            if jobs.isEmpty && idle.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(jobs) { job in
                            RunningJobCard(job: job, accent: accent)
                        }
                        ForEach(idle) { vehicle in
                            IdleVehicleCard(vehicle: vehicle, accent: accent)
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .padding(.bottom, Layout.tabBarClearance)
    }
}

private struct RunningJobCard: View {
    @Environment(GameSession.self) private var session
    let job: ActiveJob
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(vehicleCode)
                    .font(.gg(11, .heavy)).tracking(0.8)
                    .foregroundStyle(accent)
                Spacer()
                if let clock = session.state?.clock {
                    Text(Format.duration(minutes: max(0, clock.minutes(until: job.phaseEndsAt))) + " left")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text("\(cityName(job.offer.origin)) → \(cityName(job.offer.destination))")
                .font(.gg(14, .heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            ThemeProgressBar(value: phaseFraction, tint: accent, height: 6)
            HStack {
                Text(phaseTitle)
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(Format.money(job.offer.payout))
                    .font(.gg(11, .heavy))
                    .foregroundStyle(Theme.mint)
            }
        }
        .padding(14)
        .frame(width: 230, alignment: .leading)
        .surfacePanel(cornerRadius: 18)
    }

    private var phaseFraction: Double {
        guard let clock = session.state?.clock else { return 0 }
        let total = job.phaseStartedAt.minutes(until: job.phaseEndsAt)
        guard total > 0 else { return 0 }
        let done = job.phaseStartedAt.minutes(until: clock)
        return Double(done) / Double(total)
    }

    private var vehicleCode: String {
        if let vehicle = session.state?.vehicles.first(where: { $0.id == job.vehicleID }),
           let type = session.catalog.vehicleType(vehicle.typeID) {
            return type.name.uppercased()
        }
        return "VEHICLE"
    }

    private var phaseTitle: String {
        switch job.phase {
        case .deadheading: return "To pickup"
        case .loading: return "Loading"
        case .enRoute: return "En route"
        case .unloading: return "Unloading"
        }
    }

    private func cityName(_ id: CityID) -> String { session.catalog.city(id)?.name ?? id.rawValue }
}

private struct IdleVehicleCard: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(vehicleCode) • IDLE")
                .font(.gg(11, .heavy)).tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
            Text("Waiting in \(session.catalog.city(vehicle.cityID)?.name ?? "")")
                .font(.gg(13, .heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text("Find a return load →")
                .font(.gg(11.5, .heavy))
                .foregroundStyle(accent)
        }
        .padding(14)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        )
    }

    private var vehicleCode: String {
        session.catalog.vehicleType(vehicle.typeID)?.name.uppercased() ?? "VEHICLE"
    }
}

// MARK: - City detail

private struct CityDetailSheet: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID

    var body: some View {
        NavigationStack {
            List {
                if let city = session.catalog.city(cityID) {
                    Section {
                        CityFactChips(city: city)
                        if session.state?.config.hqCity == cityID {
                            Label("Company Headquarters", systemImage: "building.2")
                                .font(.subheadline)
                                .foregroundStyle(.tint)
                        }
                    }
                    .font(.subheadline)
                    .listRowBackground(Theme.surface)
                }

                let vehiclesHere = (session.state?.vehicles ?? [])
                    .filter { $0.cityID == cityID && $0.isAvailable }
                if !vehiclesHere.isEmpty {
                    Section("Vehicles Here") {
                        ForEach(vehiclesHere) { vehicle in
                            VehicleRow(vehicle: vehicle)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                let offersHere = (session.state?.offers ?? [])
                    .filter { $0.origin == cityID }
                    .sorted { $0.expiresAt < $1.expiresAt }
                Section("Outgoing Freight") {
                    if offersHere.isEmpty {
                        Text("No open offers right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(offersHere) { offer in
                            NavigationLink(value: offer.id) {
                                OfferRow(offer: offer)
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(session.catalog.city(cityID)?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: JobID.self) { offerID in
                OfferDetailView(offerID: offerID)
            }
        }
        .tint(Color(hex: session.state?.config.identity.colorHex ?? "#FFB037"))
    }
}

private struct CityFactChips: View {
    let city: CityDefinition

    var body: some View {
        HStack(spacing: 8) {
            StatChip(
                symbol: "person.2.fill",
                text: city.population.formatted(.number.notation(.compactName))
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Population"))
            .accessibilityValue(Text(city.population.formatted()))

            if city.hasRailFreightAccess {
                StatChip(symbol: "tram.fill", text: String(localized: "Rail"), tint: Theme.gold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Freight rail access"))
            }
            if city.hasAirCargoAccess {
                StatChip(symbol: "airplane", text: String(localized: "Air"), tint: Theme.gold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Air cargo access"))
            }
            if city.hasSeaPortAccess {
                StatChip(symbol: "ferry.fill", text: String(localized: "Sea"), tint: Theme.gold)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Sea port access"))
            }
        }
    }
}
