//
//  RouteBuilderView.swift
//  Goods&Glory
//
//  Strategic recurring-operation planner: the map owns the physical loop,
//  while compact city visits own the work performed at each city.
//

import SwiftUI

struct RouteBuilderView: View {
    @Environment(GameSession.self) var session
    @Environment(\.dismiss) var dismiss

    let routeID: RouteID

    @State var mapSelection: MapSelection = .none
    @State var pendingCityID: CityID?
    @State var selectedVisit: CityVisit?
    @State var showsVehiclePicker = false
    @State var showsCancellation = false
    @State var showsRename = false
    @State var showsRouteOptions = false
    @State var commandError: CommandError?
    /// Chrome toggles must not recompute the map snapshot on the main thread —
    /// that work belongs on clock / route changes only.
    @State var mapSnapshot: MapRenderSnapshot = .empty
    var accent: Color { session.accentColor }

    struct CityVisit: Identifiable, Hashable {
        let id: Int
        let cityID: CityID
        var stops: [RouteStop]
    }


    var route: Route? { session.state?.route(routeID) }

    var assignedVehicles: [Vehicle] {
        guard let state = session.state, let route else { return [] }
        return route.vehicleIDs.compactMap(state.vehicle)
    }

    var body: some View {
        Group {
            if let route {
                routeContent(route)
            } else {
                unavailableContent
            }
        }
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .tint(accent)
        .onChange(of: mapSelection) { _, selection in
            showsRouteOptions = false
            switch selection {
            case .city(let cityID):
                pendingCityID = cityID
            case .vehicle:
                mapSelection = .none
            case .none:
                pendingCityID = nil
            }
        }
        .onAppear {
            syncMapSnapshot()
            // Rename sheet uses a TextField; warm the keyboard while the map
            // is idle so the first rename does not pay the cold-start hitch.
            KeyboardPrewarm.runOnce()
        }
        .onChange(of: mapSnapshotDependency) { _, _ in syncMapSnapshot() }
        .onChange(of: showsRouteOptions) { _, open in
            if open { KeyboardPrewarm.runOnce() }
        }
        .sheet(item: $selectedVisit) { visit in
            RouteTaskPicker(
                routeID: routeID,
                visitID: visit.id,
                cityID: visit.cityID,
                accent: accent
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsVehiclePicker) {
            RouteVehiclePicker(routeID: routeID, accent: accent)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsCancellation) {
            RouteCancellationSheet(routeID: routeID, accent: accent) {
                dismiss()
            }
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsRename) {
            RouteRenameSheet(routeID: routeID, accent: accent)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "Could Not Update Route",
            isPresented: Binding(
                get: { commandError != nil },
                set: { if !$0 { commandError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(commandErrorMessage)
        }
    }

    func routeContent(_ route: Route) -> some View {
        VStack(spacing: 0) {
            mapHeader(route)
            editorPanel(route)
        }
        .background(Theme.backgroundTop.ignoresSafeArea())
    }

    func mapHeader(_ route: Route) -> some View {
        let visits = cityVisits(route)
        return ZStack(alignment: .topLeading) {
            if session.state != nil {
                InteractiveMapView(
                    catalog: session.catalog,
                    hqCityID: session.state?.config.hqCity,
                    accentColorHex: session.state?.config.identity.colorHex ?? "#FFFFFF",
                    renderSnapshot: mapSnapshot,
                    cameraFocus: visits.isEmpty
                        ? .world
                        // Strip map: editor sits below the scene, not over it —
                        // only reserve the back/title chrome.
                        : .route(cities: visits.map(\.cityID), topInset: 52, bottomInset: 16),
                    // Sheets over a live SKView contend for the main thread;
                    // sleep Metal while any modal owns the screen.
                    isRenderingEnabled: !showsRename
                        && !showsCancellation
                        && !showsVehiclePicker
                        && selectedVisit == nil,
                    selection: $mapSelection
                )
            } else {
                Theme.backgroundTop
            }

            LinearGradient(colors: [Theme.backgroundTop, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 72)
                .allowsHitTesting(false)

            // Back left, title centered — same overlay chrome idea as city
            // detail, without the old +56 dead band that ate the map strip.
            ZStack {
                VStack(spacing: 4) {
                    Text(route.name)
                        .font(.gg(17, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    TagPill(text: routeStatus(route).text, color: routeStatus(route).color)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 48)
                .allowsHitTesting(false)

                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.surfaceGlass))
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    // SwiftUI `Menu` snapshots the hosting hierarchy (including
                    // the Metal SKView) and freezes for a beat — use a plain
                    // overlay list instead.
                    Button {
                        showsRouteOptions.toggle()
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Theme.surfaceGlass))
                            .overlay(Circle().stroke(Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Route options")
                    .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 14)
            .safeAreaPadding(.top, 8)

            if showsRouteOptions {
                routeOptionsMenu(route)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
            }

            if let pendingCityID {
                citySelectionCard(pendingCityID, route: route)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 38)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsRouteOptions)
        .animation(.easeOut(duration: 0.2), value: pendingCityID)
        // Editor panel is the strategic surface; keep the map as context only.
        .frame(height: 298)
    }

    func routeOptionsMenu(_ route: Route) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showsRouteOptions = false }

            VStack(spacing: 0) {
                Button {
                    showsRouteOptions = false
                    showsRename = true
                } label: {
                    Label("Rename Route", systemImage: "pencil")
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(route.cancellationRequestedAt != nil)
                .opacity(route.cancellationRequestedAt == nil ? 1 : 0.4)

                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)

                Button {
                    showsRouteOptions = false
                    showsCancellation = true
                } label: {
                    Label(destructiveRouteActionTitle(route), systemImage: "trash")
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.coral)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(route.cancellationRequestedAt != nil)
                .opacity(route.cancellationRequestedAt == nil ? 1 : 0.4)
            }
            .frame(width: 196)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surfaceGlass)
                    .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .padding(.trailing, 14)
            .safeAreaPadding(.top, 52)
        }
    }

    func citySelectionCard(_ cityID: CityID, route: Route) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 38, height: 38)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.cityName(cityID))
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("Add as visit \(cityVisits(route).count + 1)")
                    .font(.gg(10.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 4)

            Button("Add") {
                apply(.addTravelStop(routeID: routeID, cityID: cityID))
                clearMapSelection()
            }
            .font(.gg(12, .heavy))
            .foregroundStyle(Theme.onBrand)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(accent))
            .disabled(!canAppend(route))
            .opacity(canAppend(route) ? 1 : 0.45)

            Button { clearMapSelection() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.surfaceGlass)
                .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.30), lineWidth: 1)
        )
    }

    func editorPanel(_ route: Route) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.stroke.opacity(1.5))
                .frame(width: 44, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 5)

            if route.cancellationRequestedAt != nil {
                statusNotice(
                    symbol: "xmark.circle.fill",
                    text: "Route cancellation is in progress. Loaded freight will be delivered before vehicles are released.",
                    color: Theme.coral
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            } else if isWindingDown(route) {
                statusNotice(
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    text: "Vehicles are finishing loaded freight. Editing unlocks when they are idle.",
                    color: Theme.warning
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
            }

            routeEditorList(route)
        }
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

    func routeActions(_ route: Route) -> some View {
        VStack(spacing: 8) {
            Button { showsVehiclePicker = true } label: {
                HStack(spacing: 7) {
                    Text("VEHICLES")
                        .font(.gg(9.5, .heavy))
                        .foregroundStyle(Theme.textTertiary)

                    if assignedVehicles.isEmpty {
                        Text("Assign at least one vehicle")
                            .font(.gg(11.5, .heavy))
                            .foregroundStyle(Theme.coral)
                    } else {
                        ForEach(assignedVehicles.prefix(3)) { vehicle in
                            Text(session.vehicleCode(vehicle))
                                .font(.gg(10.5, .heavy))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Theme.surface))
                        }
                        if assignedVehicles.count > 3 {
                            Text("+\(assignedVehicles.count - 3)")
                                .font(.gg(10, .heavy))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer()
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(accent)
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(route.cancellationRequestedAt != nil)

            if let vehicle = assignedVehicles.first,
               let estimate = session.estimate(route: route, vehicle: vehicle) {
                HStack(spacing: 7) {
                    metricTile("Distance", Format.distance(km: estimate.lapDistanceKm))
                    metricTile("Duration", Format.duration(minutes: estimate.lapMinutes))
                    metricTile(
                        "Est. Net",
                        Format.money(estimate.netPerLap),
                        color: estimate.netPerLap >= 0 ? Theme.mint : Theme.coral
                    )
                }
            }

            if let issue = planningIssue(route) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(issue)
                    Spacer()
                }
                .font(.gg(10.5, .bold))
                .foregroundStyle(Theme.warning)
            }

            Button {
                primaryAction(route)
            } label: {
                Label(primaryActionTitle(route), systemImage: primaryActionSymbol(route))
            }
            .buttonStyle(PrimaryButtonStyle(tint: route.isRunning ? Theme.warning : accent))
            .disabled(primaryActionDisabled(route))
            .opacity(primaryActionDisabled(route) ? 0.48 : 1)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    func metricTile(_ label: String, _ value: String, color: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.gg(8.5, .heavy))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.gg(11, .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.14)))
    }

    func statusNotice(symbol: String, text: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.gg(10.5, .bold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 13).fill(color.opacity(0.08)))
    }

    var unavailableContent: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surface))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)

            ContentUnavailableView(
                "Route Unavailable",
                systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                description: Text("This route was deleted or is no longer available.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}
