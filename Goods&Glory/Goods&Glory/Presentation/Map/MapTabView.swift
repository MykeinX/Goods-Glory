//
//  MapTabView.swift
//  Goods&Glory
//
//  In-game map tab (design 1b): full-bleed night map, floating status overlay,
//  vehicle popup and a compact fleet summary. A tapped city centers on the map
//  and opens the city sheet over it — no second screen, no back button.
//

import QuartzCore
import SwiftUI

struct MapTabView: View {
    /// False while another game tab is selected — map stays mounted but Metal sleeps.
    var isMapTabSelected: Bool = true

    @Environment(GameSession.self) private var session
    @State private var selection: MapSelection = .none
    @State private var detail: MapDetailDestination?
    /// Notification (and future) soft-pans — zoom stays as the player left it.
    @State private var cameraPanRequest: MapCameraPanRequest?
    /// Which detent the city sheet is resting at; `.large` hides the map.
    @State private var citySheetDetent: PresentationDetent = CitySheetLayout.detent
    /// Live map height, used to size the band the sheet leaves visible.
    @State private var mapHeight: CGFloat = 0
    private var accent: Color { session.accentColor }


    /// Developer HUD. Compiled out of release builds entirely.
    private var showsPerformanceHUD: Bool {
        #if DEBUG
        AppSettings.shared.showsPerformanceOverlay
        #else
        false
        #endif
    }

    /// Off-tab, under a full-screen cover, or under a fully raised city sheet:
    /// keep the scene, stop presenting. Background sleep is handled inside
    /// InteractiveMapView via scenePhase.
    private var isMapRenderingEnabled: Bool {
        guard isMapTabSelected, detail == nil else { return false }
        return !(isCitySheetOpen && citySheetDetent == .large)
    }

    private var isCitySheetOpen: Bool { selection.cityID != nil }

    /// Screen points the city sheet covers at its resting detent.
    private var citySheetInset: CGFloat {
        mapHeight * CitySheetLayout.detentFraction
    }

    private func mapSnapshot(state: GameState) -> MapRenderSnapshot {
        let projection = MapProjection()
        let startedAt = CACurrentMediaTime()
        let snapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: session.catalog,
            projection: projection
        )
        PerformanceMonitor.shared.recordSnapshot(CACurrentMediaTime() - startedAt)
        return snapshot
    }

    var body: some View {
        ZStack {
            if let state = session.state {
                InteractiveMapView(
                    catalog: session.catalog,
                    hqCityID: state.config.hqCity,
                    accentColorHex: state.config.identity.colorHex,
                    // Snapshot work is skipped while sleeping; wake forces a fresh apply.
                    renderSnapshot: isMapRenderingEnabled ? mapSnapshot(state: state) : .empty,
                    // Preserve pan/zoom across tab switches. HQ framing is applied
                    // once inside the scene on first layout.
                    cameraFocus: .free,
                    cameraPanRequest: cameraPanRequest,
                    isRenderingEnabled: isMapRenderingEnabled,
                    showsRenderStatistics: showsPerformanceHUD,
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

                if showsPerformanceHUD {
                    PerformanceOverlay(state: state)
                        .padding(.leading, 12)
                        .padding(.top, 96)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                VStack(spacing: 0) {
                    MapStatusOverlay(accent: accent)
                    Spacer()
                    MapBottomChrome(
                        accent: accent,
                        selection: $selection,
                        onOpenDetail: { detail = $0 },
                        onFocusCity: { cameraPanRequest = MapCameraPanRequest(cityID: $0) }
                    )
                }
            } else {
                Theme.backgroundTop.ignoresSafeArea()
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { mapHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in mapHeight = height }
            }
        )
        .onChange(of: selection) { _, newValue in
            guard let cityID = newValue.cityID else { return }
            // Lift the tapped city into the strip left above the sheet.
            citySheetDetent = CitySheetLayout.detent
            cameraPanRequest = MapCameraPanRequest(cityID: cityID, bottomInset: citySheetInset)
        }
        .sheet(isPresented: Binding(
            get: { isCitySheetOpen },
            set: { if !$0 { selection = .none } }
        )) {
            if let cityID = selection.cityID {
                CityDetailSheet(cityID: cityID)
                    .presentationDetents([CitySheetLayout.detent, .large], selection: $citySheetDetent)
                    .presentationDragIndicator(.visible)
                    .presentationBackgroundInteraction(.enabled(upThrough: CitySheetLayout.detent))
                    .presentationCornerRadius(26)
            }
        }
        .fullScreenCover(item: $detail) { destination in
            switch destination {
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
