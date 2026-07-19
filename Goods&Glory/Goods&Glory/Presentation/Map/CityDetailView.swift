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

    @ViewBuilder private var outboundFreightSection: some View {
        let offers = (session.state?.offers ?? [])
            .filter { $0.origin == activeCityID }
            .sorted { $0.expiresAt < $1.expiresAt }
        SectionLabel(String(localized: "Outbound freight \(offers.count)"))
        if offers.isEmpty {
            Text(String(localized: "No open offers from this city right now."))
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfacePanel(cornerRadius: 18)
        } else {
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

    private var facilitiesSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel(String(localized: "Your buildings"))
            if session.state?.config.hqCity == activeCityID {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.sky.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "building.2.fill")
                            .foregroundStyle(Theme.sky)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Headquarters"))
                            .font(.gg(13, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text(String(localized: "Company base in this city"))
                            .font(.gg(11, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(12)
                .surfacePanel(cornerRadius: 18)
            }

            HStack(spacing: 7) {
                Text("+").font(.gg(15, .heavy)).foregroundStyle(accent)
                Text(String(localized: "Build a facility"))
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.stroke.opacity(2))
            )
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
                case .pickupShipment, .pickupContract:
                    return (String(localized: "loading"), Theme.mint)
                case .deliverShipment, .deliverContract:
                    return (String(localized: "unloading"), Theme.mint)
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
