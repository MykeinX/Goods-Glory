//
//  RouteBuilderView.swift
//  Goods&Glory
//
//  Strategic recurring-operation planner: the map owns the physical loop,
//  while compact city visits own the work performed at each city.
//

import SwiftUI

struct RouteBuilderView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID

    @State private var mapSelection: MapSelection = .none
    @State private var pendingCityID: CityID?
    @State private var selectedVisit: CityVisit?
    @State private var showsVehiclePicker = false
    @State private var showsCancellation = false
    @State private var commandError: CommandError?

    private struct CityVisit: Identifiable, Hashable {
        let id: Int
        let cityID: CityID
        var stops: [RouteStop]
    }

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    private var route: Route? { session.state?.route(routeID) }

    private var assignedVehicles: [Vehicle] {
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
            switch selection {
            case .city(let cityID):
                pendingCityID = cityID
            case .vehicle:
                mapSelection = .none
            case .none:
                pendingCityID = nil
            }
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

    private func routeContent(_ route: Route) -> some View {
        VStack(spacing: 0) {
            mapHeader(route)
            editorPanel(route)
        }
        .background(Theme.backgroundTop.ignoresSafeArea())
    }

    private func mapHeader(_ route: Route) -> some View {
        let visits = cityVisits(route)
        return ZStack(alignment: .topLeading) {
            if let state = session.state {
                InteractiveMapView(
                    catalog: session.catalog,
                    hqCityID: state.config.hqCity,
                    accentColorHex: state.config.identity.colorHex,
                    renderSnapshot: MapSceneAdapter.snapshot(
                        state: state,
                        catalog: session.catalog,
                        projection: MapProjection(),
                        previewRoute: route
                    ),
                    cameraFocus: visits.isEmpty ? .world : .route(visits.map(\.cityID)),
                    selection: $mapSelection
                )
            } else {
                Theme.backgroundTop
            }

            LinearGradient(colors: [Theme.backgroundTop, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 132)
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

                VStack(alignment: .leading, spacing: 3) {
                    Text(route.name)
                        .font(.gg(21, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    TagPill(text: routeStatus(route).text, color: routeStatus(route).color)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 56)

            if let pendingCityID {
                citySelectionCard(pendingCityID, route: route)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 38)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: pendingCityID)
        .frame(height: 350)
    }

    private func citySelectionCard(_ cityID: CityID, route: Route) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(accent.opacity(0.16)).frame(width: 38, height: 38)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(cityName(cityID))
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

    private func editorPanel(_ route: Route) -> some View {
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
                .padding(.bottom, 4)
            } else if isWindingDown(route) {
                statusNotice(
                    symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    text: "Vehicles are finishing committed freight. Editing unlocks when they are idle.",
                    color: Theme.warning
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
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

    private func routeEditorList(_ route: Route) -> some View {
        let visits = cityVisits(route)
        return List {
            Section {
                if visits.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "map")
                            .foregroundStyle(accent)
                        Text("Tap a city on the map to add the first visit.")
                            .font(.gg(12, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                    .routeListRow()
                } else {
                    ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                        compactVisitRow(visit, number: index + 1, route: route)
                            .dropDestination(for: String.self) { items, location in
                                guard canEdit(route),
                                      let rawID = items.first,
                                      let draggedID = Int(rawID),
                                      draggedID != visit.id else { return false }
                                dropVisit(
                                    draggedID,
                                    on: visit.id,
                                    placeAfter: location.y > 32,
                                    route: route
                                )
                                return true
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if canEdit(route) {
                                    Button(role: .destructive) {
                                        apply(.removeRouteVisit(routeID: route.id, visitStopID: visit.id))
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }
                            .accessibilityAction(named: "Move earlier") {
                                moveVisit(visit.id, by: -1, route: route)
                            }
                            .accessibilityAction(named: "Move later") {
                                moveVisit(visit.id, by: 1, route: route)
                            }
                            .routeListRow()
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(accent)
                    Text("Add another city from the map")
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 5)
                .routeListRow()
            } header: {
                HStack {
                    Text("ROUTE PLAN")
                    Spacer()
                    Text("\(visits.count) cit\(visits.count == 1 ? "y" : "ies") · \(taskCount(route)) tasks")
                }
                .font(.gg(10.5, .heavy))
                .foregroundStyle(Theme.textTertiary)
                .textCase(nil)
            }

            Section {
                routeActions(route)
                    .routeListRow()
            }

            Color.clear
                .frame(height: Layout.tabBarClearance)
                .routeListRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func compactVisitRow(_ visit: CityVisit, number: Int, route: Route) -> some View {
        let tasks = visit.stops.filter { !isTravel($0.task) }
        return HStack(spacing: 10) {
            Text("\(number)")
                .font(.gg(12, .heavy))
                .foregroundStyle(Theme.onBrand)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent))

            VStack(alignment: .leading, spacing: 5) {
                Text(cityName(visit.cityID))
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    if tasks.isEmpty {
                        compactTaskChip(text: "Drive only", symbol: "arrow.right", color: Theme.textTertiary)
                    } else {
                        ForEach(Array(tasks.prefix(2))) { stop in
                            compactTaskChip(
                                text: taskChipText(stop.task),
                                symbol: taskSymbol(stop.task),
                                color: taskColor(stop.task)
                            )
                        }
                        if tasks.count > 2 {
                            Text("+\(tasks.count - 2)")
                                .font(.gg(9.5, .heavy))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Theme.surface))
                        }
                    }
                }
            }

            Spacer(minLength: 4)

            Button {
                selectedVisit = visit
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(canEdit(route) ? accent : Theme.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canEdit(route))
            .accessibilityLabel("Add work in \(cityName(visit.cityID))")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(canEdit(route) ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
                .draggable(String(visit.id))
                .allowsHitTesting(canEdit(route))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Theme.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }

    private func compactTaskChip(text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .heavy))
            Text(text)
                .font(.gg(9, .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 1))
    }

    private func routeActions(_ route: Route) -> some View {
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
                            Text(vehicleCode(vehicle))
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

            HStack(spacing: 8) {
                Button {
                    primaryAction(route)
                } label: {
                    Label(primaryActionTitle(route), systemImage: primaryActionSymbol(route))
                }
                .buttonStyle(PrimaryButtonStyle(tint: route.isRunning ? Theme.warning : accent))
                .disabled(primaryActionDisabled(route))
                .opacity(primaryActionDisabled(route) ? 0.48 : 1)

                Button { showsCancellation = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.coral)
                        .frame(width: 48, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Theme.coral.opacity(0.09))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Theme.coral.opacity(0.22), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(route.cancellationRequestedAt != nil)
                .opacity(route.cancellationRequestedAt == nil ? 1 : 0.4)
                .accessibilityLabel(route.isRunning ? "Cancel route" : "Delete route")
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func metricTile(_ label: String, _ value: String, color: Color = Theme.textPrimary) -> some View {
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

    private func statusNotice(symbol: String, text: String, color: Color) -> some View {
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

    private var unavailableContent: some View {
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

    private func canEdit(_ route: Route) -> Bool {
        guard let state = session.state else { return false }
        return !route.isRunning
            && route.cancellationRequestedAt == nil
            && state.routeRuns(of: route.id).isEmpty
    }

    private func canAppend(_ route: Route) -> Bool {
        route.cancellationRequestedAt == nil && !isWindingDown(route)
    }

    private func isWindingDown(_ route: Route) -> Bool {
        guard let state = session.state else { return false }
        return !route.isRunning && !state.routeRuns(of: route.id).isEmpty
    }

    private func routeStatus(_ route: Route) -> (text: String, color: Color) {
        if route.cancellationRequestedAt != nil { return ("Cancelling", Theme.coral) }
        if route.isRunning { return ("Running", Theme.mint) }
        if isWindingDown(route) { return ("Finishing Freight", Theme.warning) }
        return ("Draft", Theme.textSecondary)
    }

    private func cityVisits(_ route: Route) -> [CityVisit] {
        route.stops.reduce(into: []) { visits, stop in
            if let last = visits.indices.last, visits[last].cityID == stop.cityID {
                visits[last].stops.append(stop)
            } else {
                visits.append(CityVisit(id: stop.id, cityID: stop.cityID, stops: [stop]))
            }
        }
    }

    private func dropVisit(
        _ draggedID: Int,
        on targetID: Int,
        placeAfter: Bool,
        route: Route
    ) {
        var visits = cityVisits(route)
        guard let source = visits.firstIndex(where: { $0.id == draggedID }),
              let target = visits.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = visits.remove(at: source)
        var insertion = target
        if source < target { insertion -= 1 }
        if placeAfter { insertion += 1 }
        visits.insert(moved, at: min(max(0, insertion), visits.count))
        apply(.reorderRouteVisits(routeID: route.id, orderedVisitIDs: visits.map(\.id)))
    }

    private func moveVisit(_ id: Int, by offset: Int, route: Route) {
        guard canEdit(route) else { return }
        var visits = cityVisits(route)
        guard let source = visits.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard visits.indices.contains(destination) else { return }
        visits.swapAt(source, destination)
        apply(.reorderRouteVisits(routeID: route.id, orderedVisitIDs: visits.map(\.id)))
    }

    private func taskCount(_ route: Route) -> Int {
        route.stops.count { !isTravel($0.task) }
    }

    private func isTravel(_ task: RouteTask) -> Bool {
        if case .travel = task { return true }
        return false
    }

    private func taskSymbol(_ task: RouteTask) -> String {
        switch task {
        case .travel: return "arrow.right"
        case .pickupShipment, .pickupContract: return "tray.and.arrow.up.fill"
        case .deliverShipment, .deliverContract: return "tray.and.arrow.down.fill"
        }
    }

    private func taskColor(_ task: RouteTask) -> Color {
        switch task {
        case .travel: return Theme.textTertiary
        case .pickupShipment, .pickupContract: return accent
        case .deliverShipment, .deliverContract: return Theme.mint
        }
    }

    private func taskChipText(_ task: RouteTask) -> String {
        switch task {
        case .travel:
            return "Drive"
        case .pickupContract(let contractID):
            return "PICK UP · \(contractFirm(contractID, pickup: true))"
        case .deliverContract(let contractID):
            return "DELIVER · \(contractFirm(contractID, pickup: false))"
        case .pickupShipment:
            return "ONE-OFF PICKUP"
        case .deliverShipment:
            return "ONE-OFF DELIVERY"
        }
    }

    private func contractFirm(_ contractID: ContractID, pickup: Bool) -> String {
        guard let contract = session.state?.activeContract(contractID) else { return "Ended contract" }
        let firmID = pickup ? contract.originFirmID : contract.destinationFirmID
        return firmID.flatMap(session.catalog.firm)?.name ?? cityName(pickup ? contract.origin : contract.destination)
    }

    private func cityName(_ id: CityID) -> String {
        session.catalog.city(id)?.name ?? id.rawValue
    }

    private func vehicleCode(_ vehicle: Vehicle) -> String {
        let typeName = session.catalog.vehicleType(vehicle.typeID)?.name ?? "VEH"
        return Format.vehicleCode(typeName: typeName, id: vehicle.id)
    }

    private func planningIssue(_ route: Route) -> String? {
        if route.stops.isEmpty { return "Add at least one city." }
        if assignedVehicles.isEmpty { return "Assign a vehicle before starting." }
        let contractTasks = route.stops.compactMap { stop -> (ContractID, Bool)? in
            switch stop.task {
            case .pickupContract(let id): return (id, true)
            case .deliverContract(let id): return (id, false)
            default: return nil
            }
        }
        for id in Set(contractTasks.map(\.0)) {
            let entries = contractTasks.filter { $0.0 == id }
            if !entries.contains(where: { $0.1 }) || !entries.contains(where: { !$0.1 }) {
                return "Every contract pickup needs a matching delivery on this route."
            }
        }
        return nil
    }

    private func primaryActionTitle(_ route: Route) -> String {
        if route.cancellationRequestedAt != nil { return "Cancelling Route" }
        if route.isRunning { return "Stop Route" }
        if isWindingDown(route) { return "Finishing Freight" }
        if assignedVehicles.isEmpty { return "Assign Vehicle" }
        return "Start Route"
    }

    private func primaryActionSymbol(_ route: Route) -> String {
        if route.cancellationRequestedAt != nil { return "hourglass" }
        if route.isRunning { return "stop.fill" }
        if isWindingDown(route) { return "clock.fill" }
        if assignedVehicles.isEmpty { return "truck.box.badge.plus" }
        return "play.fill"
    }

    private func primaryActionDisabled(_ route: Route) -> Bool {
        route.cancellationRequestedAt != nil
            || isWindingDown(route)
            || (!route.isRunning && assignedVehicles.isEmpty == false && planningIssue(route) != nil)
    }

    private func primaryAction(_ route: Route) {
        if route.isRunning {
            apply(.stopRoute(route.id))
        } else if assignedVehicles.isEmpty {
            showsVehiclePicker = true
        } else {
            apply(.startRoute(route.id))
        }
    }

    private func clearMapSelection() {
        pendingCityID = nil
        mapSelection = .none
    }

    private func apply(_ command: GameCommand) {
        if let error = session.perform(command) {
            commandError = error
        }
    }

    private var commandErrorMessage: String {
        switch commandError {
        case .insufficientFunds(let required):
            return "This action requires \(Format.money(required))."
        case .vehicleBusy:
            return "That vehicle is still busy or carrying freight."
        case .offerExpired:
            return "The selected shipment has expired."
        case .loadExceedsCapacity:
            return "The shipment does not fit the selected vehicle."
        case .noRoute:
            return "Add at least one reachable city before starting."
        case .noVehicleAssigned:
            return "Assign at least one vehicle before starting this route."
        case .incompleteRouteTasks:
            return "Each recurring pickup needs a matching delivery task."
        case .vehicleAlreadyAssigned:
            return "That vehicle already serves another route."
        case .routeIsRunning:
            return "Stop the route and wait for committed freight before editing."
        case .unknownReference, nil:
            return "The route or selected item is no longer available."
        }
    }
}

private struct RouteTaskPicker: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    let visitID: Int
    let cityID: CityID
    let accent: Color

    @State private var commandError: CommandError?

    private struct TaskOption: Identifiable {
        let contract: ActiveContract
        let action: ContractRouteAction
        var id: String { "\(contract.id.rawValue)-\(action == .pickup ? "pickup" : "deliver")" }
    }

    private var options: [TaskOption] {
        guard let state = session.state else { return [] }
        return state.activeContracts
            .flatMap { contract -> [TaskOption] in
                var result: [TaskOption] = []
                if contract.origin == cityID { result.append(TaskOption(contract: contract, action: .pickup)) }
                if contract.destination == cityID { result.append(TaskOption(contract: contract, action: .deliver)) }
                return result
            }
            .sorted { lhs, rhs in
                if lhs.contract.id == rhs.contract.id { return lhs.action == .pickup }
                return lhs.contract.id.rawValue < rhs.contract.id.rawValue
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recurring work in \(cityName)")
                        .font(.gg(12, .bold))
                        .foregroundStyle(Theme.textSecondary)

                    if options.isEmpty {
                        ContentUnavailableView(
                            "No Recurring Work",
                            systemImage: "shippingbox",
                            description: Text("Sign a contract connected to this city to add pickup or delivery work.")
                        )
                        .frame(minHeight: 220)
                    } else {
                        ForEach(options) { option in
                            taskOptionRow(option)
                        }
                    }
                }
                .padding(14)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationTitle("City Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.gg(12.5, .heavy))
                }
            }
            .alert(
                "Could Not Update Work",
                isPresented: Binding(
                    get: { commandError != nil },
                    set: { if !$0 { commandError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Stop the route and wait for its vehicles before changing recurring work.")
            }
        }
    }

    private func taskOptionRow(_ option: TaskOption) -> some View {
        let selectedStop = matchingStop(option)
        let pickup = option.action == .pickup
        let firmID = pickup ? option.contract.originFirmID : option.contract.destinationFirmID
        let firm = firmID.flatMap(session.catalog.firm)?.name ?? cityName
        let product = session.catalog.product(option.contract.productID)?.name ?? "Freight"
        let pending = session.state?.offers.count {
            $0.source == .contract && $0.contractID == option.contract.id
        } ?? 0

        return Button {
            let command: GameCommand
            if let selectedStop {
                command = .removeRouteStop(routeID: routeID, stopID: selectedStop.id)
            } else {
                command = .addContractTaskToRoute(
                    routeID: routeID,
                    visitStopID: visitID,
                    contractID: option.contract.id,
                    action: option.action
                )
            }
            commandError = session.perform(command)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((pickup ? accent : Theme.mint).opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: pickup ? "tray.and.arrow.up.fill" : "tray.and.arrow.down.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(pickup ? accent : Theme.mint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(pickup ? "Pick up contract freight" : "Deliver contract freight")
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(firm) · \(product) · \(Format.mass(kg: option.contract.shipmentMassKg))")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text("\(pending) waiting · every \(Format.duration(minutes: option.contract.shipmentIntervalMinutes))")
                        .font(.gg(9.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 4)
                Image(systemName: selectedStop == nil ? "plus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(selectedStop == nil ? accent : Theme.mint)
            }
            .padding(12)
            .surfacePanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func matchingStop(_ option: TaskOption) -> RouteStop? {
        session.state?.route(routeID)?.stops.first { stop in
            switch (option.action, stop.task) {
            case (.pickup, .pickupContract(let id)): return id == option.contract.id
            case (.deliver, .deliverContract(let id)): return id == option.contract.id
            default: return false
            }
        }
    }

    private var cityName: String {
        session.catalog.city(cityID)?.name ?? cityID.rawValue
    }
}

private struct RouteVehiclePicker: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    let accent: Color

    @State private var commandError: CommandError?

    private var route: Route? { session.state?.route(routeID) }

    private var assigned: [Vehicle] {
        guard let state = session.state, let route else { return [] }
        return route.vehicleIDs.compactMap(state.vehicle)
    }

    private var available: [Vehicle] {
        guard let state = session.state else { return [] }
        return state.vehicles
            .filter { state.isVehicleIdle($0.id) && state.route(of: $0.id) == nil }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                if !assigned.isEmpty {
                    Section("ASSIGNED") {
                        ForEach(assigned) { vehicle in
                            vehicleRow(vehicle, assigned: true)
                        }
                    }
                }

                Section("IDLE VEHICLES") {
                    if available.isEmpty {
                        Text("No idle vehicles are available.")
                            .font(.gg(12, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(available) { vehicle in
                            vehicleRow(vehicle, assigned: false)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundBottom)
            .navigationTitle("Route Vehicles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.gg(12.5, .heavy))
                }
            }
            .alert(
                "Could Not Update Vehicles",
                isPresented: Binding(
                    get: { commandError != nil },
                    set: { if !$0 { commandError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That vehicle is busy, carrying freight, or already assigned to another route.")
            }
        }
    }

    private func vehicleRow(_ vehicle: Vehicle, assigned isAssigned: Bool) -> some View {
        Button {
            commandError = session.perform(
                isAssigned
                    ? .unassignVehicleFromRoute(routeID: routeID, vehicleID: vehicle.id)
                    : .assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id)
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "truck.box.fill")
                    .foregroundStyle(isAssigned ? Theme.mint : accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicleCode(vehicle))
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(session.catalog.city(vehicle.cityID)?.name ?? vehicle.cityID.rawValue)
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: isAssigned ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isAssigned ? Theme.mint : accent)
            }
        }
        .buttonStyle(.plain)
    }

    private func vehicleCode(_ vehicle: Vehicle) -> String {
        let typeName = session.catalog.vehicleType(vehicle.typeID)?.name ?? "VEH"
        return Format.vehicleCode(typeName: typeName, id: vehicle.id)
    }
}

private struct RouteCancellationSheet: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    let accent: Color
    let onRequested: () -> Void

    @State private var commandError: CommandError?

    private var route: Route? { session.state?.route(routeID) }
    private var hasRuns: Bool { !(session.state?.routeRuns(of: routeID).isEmpty ?? true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    Circle().fill(Theme.coral.opacity(0.12)).frame(width: 44, height: 44)
                    Image(systemName: "trash.fill")
                        .foregroundStyle(Theme.coral)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hasRuns ? "Cancel this route?" : "Delete this route?")
                        .font(.gg(20, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(route?.name ?? "Route")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            Text(
                hasRuns
                    ? "New pickups stop immediately. Empty vehicles become idle at their next safe city; loaded vehicles complete committed deliveries first. The route then deletes itself."
                    : "The route is removed immediately. Assigned vehicles remain idle in their current cities."
            )
            .font(.gg(12, .bold))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button {
                commandError = session.perform(.deleteRoute(routeID))
                guard commandError == nil else { return }
                dismiss()
                onRequested()
            } label: {
                Text(hasRuns ? "Cancel Route" : "Delete Route")
            }
            .buttonStyle(PrimaryButtonStyle(tint: Theme.coral))

            Button("Keep Route") { dismiss() }
                .font(.gg(12.5, .heavy))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .padding(18)
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .alert(
            "Could Not Cancel Route",
            isPresented: Binding(
                get: { commandError != nil },
                set: { if !$0 { commandError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The route changed before it could be cancelled. Please try again.")
        }
    }
}

private extension View {
    func routeListRow() -> some View {
        listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
