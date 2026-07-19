//
//  MapTabView.swift
//  Goods&Glory
//
//  In-game map tab (design 1b): full-bleed night map, floating status overlay,
//  vehicle/city info popup and a compact fleet summary. Spot jobs from a city
//  are accepted from the city popup; deeper city info opens via detail CTA.
//

import SwiftUI

private enum MapDetailDestination: Identifiable {
    case city(CityID)
    case vehicle(VehicleID)

    var id: String {
        switch self {
        case .city(let id): return "city-\(id.rawValue)"
        case .vehicle(let id): return "vehicle-\(id.rawValue)"
        }
    }
}

struct MapTabView: View {
    @Environment(GameSession.self) private var session
    @State private var selection: MapSelection = .none
    @State private var detail: MapDetailDestination?
    /// Spot offer shown inside the city card — drives map arc + camera fit.
    @State private var spotPreviewOfferID: JobID?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    private var spotPreviewOffer: JobOffer? {
        guard let spotPreviewOfferID else { return nil }
        return session.state?.offers.first { $0.id == spotPreviewOfferID }
    }

    private var mapCameraFocus: MapCameraFocus {
        guard let offer = spotPreviewOffer else {
            // Preserve pan/zoom across tab switches and after leaving a spot preview.
            // HQ framing is applied once inside the scene on first layout.
            return .free
        }
        return .route(
            cities: [offer.origin, offer.destination],
            // City card + fleet chips + floating tab bar — bias framing upward.
            bottomInset: Layout.tabBarClearance + 280
        )
    }

    private func mapSnapshot(state: GameState) -> MapRenderSnapshot {
        let projection = MapProjection()
        let snapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: session.catalog,
            projection: projection
        )
        guard let offer = spotPreviewOffer,
              let origin = session.catalog.city(offer.origin),
              let destination = session.catalog.city(offer.destination) else {
            return snapshot
        }
        let preview = MapRouteOverlay(
            id: "spot-preview-\(offer.id.rawValue)",
            anchors: [projection.point(for: origin), projection.point(for: destination)],
            kind: .preview
        )
        return MapRenderSnapshot(
            vehicles: snapshot.vehicles,
            routes: snapshot.routes + [preview],
            plannedVisits: snapshot.plannedVisits,
            idleFleetByCity: snapshot.idleFleetByCity
        )
    }

    var body: some View {
        ZStack {
            if let state = session.state {
                InteractiveMapView(
                    catalog: session.catalog,
                    hqCityID: state.config.hqCity,
                    accentColorHex: state.config.identity.colorHex,
                    renderSnapshot: mapSnapshot(state: state),
                    cameraFocus: mapCameraFocus,
                    selection: $selection
                )
                .ignoresSafeArea()

                LinearGradient(colors: [Theme.backgroundTop, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 190)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                LinearGradient(colors: [.clear, Theme.backgroundTop.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 280)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MapStatusOverlay(accent: accent)
                    Spacer()
                    MapBottomChrome(
                        accent: accent,
                        selection: $selection,
                        spotPreviewOfferID: $spotPreviewOfferID,
                        onOpenDetail: { detail = $0 }
                    )
                }
            } else {
                Theme.backgroundTop.ignoresSafeArea()
            }
        }
        .onChange(of: selection) { _, newValue in
            if case .city = newValue { return }
            spotPreviewOfferID = nil
        }
        .fullScreenCover(item: $detail) { destination in
            switch destination {
            case .city(let id):
                CityDetailView(cityID: id)
            case .vehicle(let id):
                NavigationStack {
                    VehicleDetailView(vehicleID: id)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(String(localized: "Close")) { detail = nil }
                            }
                        }
                }
            }
        }
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

// MARK: - Bottom chrome (popup + fleet summary)

private struct MapBottomChrome: View {
    @Environment(GameSession.self) private var session
    var accent: Color
    @Binding var selection: MapSelection
    @Binding var spotPreviewOfferID: JobID?
    var onOpenDetail: (MapDetailDestination) -> Void

    private var onRouteCount: Int {
        guard let state = session.state else { return 0 }
        return state.vehicles.count { !state.isVehicleIdle($0.id) }
    }

    private var idleCount: Int {
        guard let state = session.state else { return 0 }
        return state.vehicles.count { state.isVehicleIdle($0.id) }
    }

    var body: some View {
        VStack(spacing: 10) {
            GameNotificationStack(notifications: session.notifications, accent: accent)
                .padding(.horizontal, 14)

            switch selection {
            case .none:
                EmptyView()
            case .city(let id):
                MapCityPopup(
                    cityID: id,
                    accent: accent,
                    focusedOfferID: $spotPreviewOfferID,
                    onClose: {
                        spotPreviewOfferID = nil
                        selection = .none
                    },
                    onOpenDetail: { onOpenDetail(.city(id)) }
                )
                .padding(.horizontal, 14)
            case .vehicle(let id):
                MapVehiclePopup(
                    vehicleID: id,
                    accent: accent,
                    onClose: { selection = .none },
                    onOpenDetail: { onOpenDetail(.vehicle(id)) }
                )
                .padding(.horizontal, 14)
            }

            HStack(spacing: 8) {
                MapFleetStatChip(
                    systemImage: "truck.box.fill",
                    tint: accent,
                    count: onRouteCount,
                    label: String(localized: "on route")
                )
                MapFleetStatChip(
                    systemImage: "truck.box",
                    tint: Theme.textSecondary,
                    count: idleCount,
                    label: String(localized: "idle")
                )
            }
            .padding(.horizontal, 14)
        }
        // Sit the fleet chips closer to the tab bar (was floating too high).
        .padding(.bottom, Layout.tabBarClearance - 12)
    }
}

// MARK: - Session notifications (log-backed toasts)

private struct GameNotificationStack: View {
    let notifications: [GameNotification]
    var accent: Color

    var body: some View {
        VStack(spacing: 6) {
            ForEach(notifications) { note in
                GameNotificationBanner(notification: note, accent: accent)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: notifications)
    }
}

private struct GameNotificationBanner: View {
    let notification: GameNotification
    var accent: Color

    private var tint: Color {
        switch notification.chrome {
        case .brand: return accent
        case .success: return Theme.mint
        case .warning: return Theme.coral
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: notification.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(notification.detail)
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

private struct MapFleetStatChip: View {
    let systemImage: String
    let tint: Color
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(label)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Selection popups

private struct MapCityPopup: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID
    var accent: Color
    @Binding var focusedOfferID: JobID?
    var onClose: () -> Void
    var onOpenDetail: () -> Void

    private static let previewLimit = 3
    /// Accept UI needs more vertical room than a single-offer browse card.
    private static let minimumAcceptHeight: CGFloat = 292

    @State private var showsAllSpots = false
    @State private var selectedVehicleID: VehicleID?
    @State private var commandError: CommandError?
    /// Keeps accept mode from stretching the card taller than the browse layout.
    @State private var browseCardHeight: CGFloat = 0

    private var acceptCardHeight: CGFloat? {
        guard focusedOfferID != nil else { return nil }
        guard browseCardHeight > 0 else { return Self.minimumAcceptHeight }
        return max(browseCardHeight, Self.minimumAcceptHeight)
    }

    private var city: CityDefinition? { session.catalog.city(cityID) }
    private var insight: CityInsight? {
        city.map { CityInsight.make(city: $0, catalog: session.catalog) }
    }
    private var isHQ: Bool { session.state?.config.hqCity == cityID }
    private var vehiclesHere: Int {
        session.state?.vehicles.filter { $0.cityID == cityID && $0.isAvailable }.count ?? 0
    }
    private var spotOffers: [JobOffer] {
        (session.state?.offers ?? [])
            .filter { $0.origin == cityID && $0.source == .spot }
            .sorted { $0.expiresAt < $1.expiresAt }
    }
    private var listedOffers: [JobOffer] {
        showsAllSpots ? spotOffers : Array(spotOffers.prefix(Self.previewLimit))
    }
    private var focusedOffer: JobOffer? {
        guard let focusedOfferID else { return nil }
        return session.state?.offers.first { $0.id == focusedOfferID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let offer = focusedOffer {
                acceptContent(offer)
            } else {
                browseContent
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: MapCityPopupHeightKey.self,
                                value: proxy.size.height
                            )
                        }
                    )
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: acceptCardHeight,
            maxHeight: acceptCardHeight,
            alignment: .top
        )
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.sky.opacity(0.35), lineWidth: 1.5)
        )
        .onPreferenceChange(MapCityPopupHeightKey.self) { height in
            guard height > 0 else { return }
            browseCardHeight = height
        }
        .animation(.easeOut(duration: 0.18), value: focusedOfferID)
        .onChange(of: cityID) { _, _ in
            resetAcceptState()
            showsAllSpots = false
            browseCardHeight = 0
        }
        .alert(
            "Could Not Assign Job",
            isPresented: Binding(get: { commandError != nil }, set: { if !$0 { commandError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(acceptErrorMessage)
        }
    }

    private var browseContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(city?.name ?? cityID.rawValue)
                    .font(.gg(16, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                TagPill(text: isHQ ? String(localized: "HQ") : String(localized: "City"), color: Theme.sky)
                Spacer(minLength: 8)
                closeButton(action: onClose)
            }

            chipRow(statusChips)
            spotSection

            detailCTA(
                title: String(localized: "City details →"),
                border: Theme.sky.opacity(0.35),
                action: onOpenDetail
            )
        }
    }

    private func acceptContent(_ offer: JobOffer) -> some View {
        let destination = session.catalog.city(offer.destination)?.name ?? offer.destination.rawValue
        let localVehicles = localVehiclesForAccept(offer: offer)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    resetAcceptState()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.surface))
                }
                .buttonStyle(.plain)

                Text(String(localized: "Spot job"))
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                TagPill(text: destination, color: accent)
                Spacer(minLength: 4)
                closeButton(action: onClose)
            }

            HStack(spacing: 6) {
                acceptStat(Format.money(offer.payout), tint: Theme.mint)
                acceptStat(Format.mass(kg: offer.load.massKg))
                acceptStat(Format.distance(km: offer.distanceKm))
            }

            Text(String(localized: "Vehicles here"))
                .font(.gg(10.5, .heavy))
                .foregroundStyle(Theme.textTertiary)

            if localVehicles.isEmpty {
                Text(String(localized: "No idle vehicle in this city for this load."))
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(localVehicles) { vehicle in
                            let estimate = session.estimate(offer: offer, vehicle: vehicle)
                            Button {
                                selectedVehicleID = vehicle.id
                            } label: {
                                MapSpotVehicleRow(
                                    vehicle: vehicle,
                                    estimate: estimate,
                                    isSelected: selectedVehicleID == vehicle.id,
                                    accent: accent
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(estimate == nil)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            Button {
                accept(offer)
            } label: {
                Text(String(localized: "Accept Job"))
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.onBrand)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(selectedVehicleID == nil)
            .opacity(selectedVehicleID == nil ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            preselectVehicle(from: localVehicles)
        }
        .onChange(of: offer.id) { _, _ in
            selectedVehicleID = nil
            preselectVehicle(from: localVehiclesForAccept(offer: offer))
        }
    }

    @ViewBuilder
    private var spotSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(String(localized: "Spot jobs"))
                    .font(.gg(10.5, .heavy))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if !spotOffers.isEmpty {
                    Text("\(spotOffers.count)")
                        .font(.gg(10.5, .heavy))
                        .foregroundStyle(accent)
                }
            }

            if listedOffers.isEmpty {
                Text(String(localized: "No spot jobs from this city right now."))
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                Group {
                    if showsAllSpots, spotOffers.count > Self.previewLimit {
                        ScrollView {
                            spotOfferRows
                        }
                        .frame(maxHeight: 220)
                    } else {
                        spotOfferRows
                    }
                }

                if spotOffers.count > Self.previewLimit {
                    Button {
                        showsAllSpots.toggle()
                    } label: {
                        Text(
                            showsAllSpots
                                ? String(localized: "Show fewer")
                                : String(localized: "See all \(spotOffers.count) jobs")
                        )
                        .font(.gg(12, .heavy))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var spotOfferRows: some View {
        VStack(spacing: 7) {
            ForEach(listedOffers) { offer in
                Button {
                    focusedOfferID = offer.id
                    selectedVehicleID = nil
                    commandError = nil
                } label: {
                    MapCitySpotRow(offer: offer, accent: accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var statusChips: [MapPopupChip] {
        var items: [MapPopupChip] = []
        if isHQ {
            items.append(.init(text: String(localized: "Head office"), emphasized: true))
        }
        for perk in insight?.perkLabels.prefix(2) ?? [] {
            items.append(.init(text: perk, emphasized: false))
        }
        if vehiclesHere > 0 {
            items.append(.init(
                text: String(localized: "\(vehiclesHere) idle here"),
                emphasized: true
            ))
        }
        if items.isEmpty {
            items.append(.init(text: String(localized: "No idle vehicles here"), emphasized: false))
        }
        return items
    }

    private func localVehiclesForAccept(offer: JobOffer) -> [Vehicle] {
        guard let state = session.state else { return [] }
        return state.vehicles
            .filter { $0.cityID == cityID && state.isVehicleIdle($0.id) }
            .filter { session.estimate(offer: offer, vehicle: $0) != nil }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func preselectVehicle(from vehicles: [Vehicle]) {
        guard selectedVehicleID == nil, let first = vehicles.first else { return }
        selectedVehicleID = first.id
    }

    private func accept(_ offer: JobOffer) {
        guard let selectedVehicleID else { return }
        if let error = session.perform(.acceptJob(offerID: offer.id, vehicleID: selectedVehicleID)) {
            commandError = error
        } else {
            onClose()
        }
    }

    private func resetAcceptState() {
        focusedOfferID = nil
        selectedVehicleID = nil
        commandError = nil
    }

    private func acceptStat(_ text: String, tint: Color = Theme.textSecondary) -> some View {
        Text(text)
            .font(.gg(11, .heavy))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.surface)
            )
    }

    private var acceptErrorMessage: LocalizedStringKey {
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
}

private struct MapCityPopupHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MapSpotVehicleRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    let estimate: SimulationEngine.JobEstimate?
    let isSelected: Bool
    var accent: Color

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let type = session.catalog.vehicleType(vehicle.typeID) {
                    Text(String(localized: String.LocalizationValue(type.name)))
                        .font(.gg(12.5, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let estimate {
                    HStack(spacing: 8) {
                        Text(Format.money(estimate.estimatedProfit))
                            .foregroundStyle(estimate.estimatedProfit >= 0 ? Theme.mint : Theme.coral)
                        Text(Format.duration(minutes: estimate.totalMinutes))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .font(.gg(10.5, .bold))
                }
            }
            Spacer(minLength: 4)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? accent : Theme.textTertiary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? accent.opacity(0.12) : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? accent.opacity(0.45) : Theme.strokeSoft, lineWidth: 1)
        )
    }
}

private struct MapCitySpotRow: View {
    @Environment(GameSession.self) private var session
    let offer: JobOffer
    var accent: Color

    private var destinationName: String {
        session.catalog.city(offer.destination)?.name ?? offer.destination.rawValue
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "→ \(destinationName)"))
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(Format.mass(kg: offer.load.massKg))
                    Text(Format.distance(km: offer.distanceKm))
                    if let clock = session.state?.clock {
                        Text(Format.duration(minutes: max(0, clock.minutes(until: offer.expiresAt))))
                    }
                }
                .font(.gg(10.5, .bold))
                .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 4)
            Text(Format.money(offer.payout))
                .font(.gg(13, .heavy))
                .foregroundStyle(Theme.mint)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct MapVehiclePopup: View {
    @Environment(GameSession.self) private var session
    let vehicleID: VehicleID
    var accent: Color
    var onClose: () -> Void
    var onOpenDetail: () -> Void

    private var vehicle: Vehicle? {
        session.state?.vehicles.first { $0.id == vehicleID }
    }
    private var type: VehicleTypeDefinition? {
        vehicle.flatMap { session.catalog.vehicleType($0.typeID) }
    }
    private var job: ActiveJob? {
        session.state?.activeJobs.first { $0.vehicleID == vehicleID }
    }
    private var run: RouteRun? {
        session.state?.routeRun(for: vehicleID)
    }
    private var route: Route? {
        guard let run else { return nil }
        return session.state?.route(run.routeID)
    }
    private var currentStop: RouteStop? {
        guard let run, let route, route.stops.indices.contains(run.stopIndex) else { return nil }
        return route.stops[run.stopIndex]
    }
    private var isActive: Bool { run != nil || job != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(code)
                    .font(.gg(16, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                TagPill(
                    text: statusTag,
                    color: isActive ? Theme.mint : Theme.textSecondary
                )
                Spacer(minLength: 8)
                closeButton(action: onClose)
            }

            Text(subtitle)
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)

            chipRow(chips)

            detailCTA(
                title: String(localized: "Go to vehicle detail →"),
                border: accent.opacity(0.35),
                action: onOpenDetail
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var code: String {
        Format.vehicleCode(typeName: type?.name ?? "VEH", id: vehicleID)
    }

    private var statusTag: String {
        if let run {
            switch run.phase {
            case .traveling: return String(localized: "On route")
            case .servicing: return serviceStatus
            case .waiting:
                return waitingForCargo
                    ? String(localized: "Waiting for cargo")
                    : String(localized: "Waiting")
            }
        }
        guard let job else { return String(localized: "Idle") }
        switch job.phase {
        case .deadheading: return String(localized: "To pickup")
        case .loading: return String(localized: "Loading")
        case .enRoute: return String(localized: "On route")
        case .unloading: return String(localized: "Unloading")
        }
    }

    private var subtitle: String {
        guard let vehicle else { return String(localized: "Vehicle unavailable") }
        if let run, let stop = currentStop {
            let from = session.catalog.city(run.legOriginCityID)?.name ?? run.legOriginCityID.rawValue
            let to = session.catalog.city(stop.cityID)?.name ?? stop.cityID.rawValue
            switch run.phase {
            case .traveling:
                let eta = remainingTime(until: run.phaseEndsAt)
                return "\(from) → \(to) · \(eta) left"
            case .servicing:
                let eta = remainingTime(until: run.phaseEndsAt)
                return "\(serviceStatus) in \(to) · \(eta) left"
            case .waiting:
                return waitingForCargo
                    ? String(localized: "Waiting for cargo in \(to)")
                    : String(localized: "Waiting in \(to)")
            }
        }
        if let job, let clock = session.state?.clock {
            let eta = Format.duration(minutes: max(0, clock.minutes(until: job.phaseEndsAt)))
            switch job.phase {
            case .deadheading:
                let from = cityName(vehicle.cityID)
                let to = cityName(job.offer.origin)
                return String(localized: "\(from) → \(to) · \(eta) left")
            case .loading:
                return String(localized: "Loading in \(cityName(job.offer.origin)) · \(eta) left")
            case .enRoute:
                let from = cityName(job.offer.origin)
                let to = cityName(job.offer.destination)
                return String(localized: "\(from) → \(to) · \(eta) left")
            case .unloading:
                return String(localized: "Unloading in \(cityName(job.offer.destination)) · \(eta) left")
            }
        }
        let city = session.catalog.city(vehicle.cityID)?.name ?? ""
        return String(localized: "Waiting in \(city)")
    }

    private var chips: [MapPopupChip] {
        var items: [MapPopupChip] = []
        if let type {
            items.append(.init(
                text: String(localized: String.LocalizationValue(type.name)),
                emphasized: false
            ))
        }
        if run != nil {
            if let route {
                items.append(.init(text: route.name, emphasized: true))
            }
            if let state = session.state {
                let load = state.cargoLoad(of: vehicleID)
                if load.massKg > 0 {
                    items.append(.init(text: Format.mass(kg: load.massKg), emphasized: true))
                    if let type, type.capacity.massKg > 0 {
                        let fill = min(1, Double(load.massKg) / Double(type.capacity.massKg))
                        let percent = Int((fill * 100).rounded())
                        items.append(.init(
                            text: String(localized: "\(percent)% full"),
                            emphasized: false
                        ))
                    }
                } else {
                    items.append(.init(text: String(localized: "Empty"), emphasized: false))
                }
            }
        } else if let job {
            switch job.phase {
            case .deadheading:
                items.append(.init(text: String(localized: "Empty"), emphasized: false))
            case .loading:
                items.append(.init(
                    text: String(localized: "Loading \(Format.mass(kg: job.offer.load.massKg))"),
                    emphasized: true
                ))
            case .enRoute, .unloading:
                items.append(.init(text: Format.mass(kg: job.offer.load.massKg), emphasized: true))
            }
            if let product = session.catalog.product(job.offer.productID) {
                items.append(.init(
                    text: String(localized: String.LocalizationValue(product.name)),
                    emphasized: false
                ))
            }
            if job.phase == .enRoute || job.phase == .unloading,
               let type, type.capacity.massKg > 0 {
                let fill = min(1, Double(job.offer.load.massKg) / Double(type.capacity.massKg))
                let percent = Int((fill * 100).rounded())
                items.append(.init(
                    text: String(localized: "\(percent)% full"),
                    emphasized: false
                ))
            }
        } else {
            items.append(.init(text: String(localized: "Find a return load"), emphasized: true))
        }
        return items
    }

    private var serviceStatus: String {
        guard let currentStop else { return String(localized: "Servicing") }
        switch currentStop.task {
        case .pickupShipment, .pickupContract: return String(localized: "Loading")
        case .deliverShipment, .deliverContract: return String(localized: "Unloading")
        case .travel: return String(localized: "Servicing")
        }
    }

    private var waitingForCargo: Bool {
        guard let run, run.phase == .waiting,
              let currentStop,
              case .pickupContract(let contractID) = currentStop.task else { return false }
        return session.state?.activeContract(contractID) != nil
    }

    private func remainingTime(until end: GameTime) -> String {
        guard let clock = session.state?.clock else { return Format.duration(minutes: 0) }
        return Format.duration(minutes: max(0, clock.minutes(until: end)))
    }

    private func cityName(_ id: CityID) -> String {
        session.catalog.city(id)?.name ?? id.rawValue
    }
}

private struct MapPopupChip: Identifiable {
    var id: String { text }
    let text: String
    let emphasized: Bool
}

private func chipRow(_ chips: [MapPopupChip]) -> some View {
    FlowWrappingHStack(spacing: 6) {
        ForEach(chips) { chip in
            Text(chip.text)
                .font(.gg(11, .heavy))
                .foregroundStyle(chip.emphasized ? Theme.brand : Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        chip.emphasized
                            ? Theme.brand.opacity(0.12)
                            : Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.10)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        chip.emphasized ? Theme.brand.opacity(0.3) : Theme.strokeSoft,
                        lineWidth: 1
                    )
                )
        }
    }
}

private func closeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.12)))
    }
    .buttonStyle(.plain)
}

private func detailCTA(title: String, border: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.gg(12.5, .heavy))
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.brand.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
}

/// Simple wrapping row for popup chips (avoids a heavier layout dependency).
private struct FlowWrappingHStack: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            height = max(height, y + rowHeight)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
