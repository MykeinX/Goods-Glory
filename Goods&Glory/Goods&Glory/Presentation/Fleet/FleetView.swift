//
//  FleetView.swift
//  Goods&Glory
//
//  Fleet tab (design 3b): Routes / Vehicles / Shop segments. Routes are a
//  visual shell; vehicles and shop use live catalog/state data.
//

import SwiftUI

private enum FleetMode: CaseIterable {
    case routes, vehicles, shop
    var title: String {
        switch self {
        case .routes: return "Routes"
        case .vehicles: return "Vehicles"
        case .shop: return "Shop"
        }
    }
}

private enum VehicleFilter: String, CaseIterable {
    case all = "All"
    case idle = "Idle"
    case onRoute = "On route"
}

private struct RouteActionSelection: Identifiable {
    let routeID: RouteID
    var id: Int { routeID.rawValue }
}

struct FleetView: View {
    @Environment(GameSession.self) private var session
    @State private var path = NavigationPath()
    @State private var mode: FleetMode = .vehicles
    @State private var vehicleFilter: VehicleFilter = .all
    @State private var purchaseError: CommandError?
    @State private var routeActionSelection: RouteActionSelection?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    private var vehicles: [Vehicle] { session.state?.vehicles ?? [] }
    private var routes: [Route] { session.state?.routes ?? [] }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(
                    title: "Fleet",
                    trailing: "\(vehicles.count) vehicles · \(routes.count) routes"
                )
                .padding(.horizontal, 14)

                fleetModePicker
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch mode {
                        case .routes: routesContent
                        case .vehicles: vehiclesContent
                        case .shop: shopContent
                        }
                        Color.clear.frame(height: Layout.tabBarClearance)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationDestination(for: VehicleID.self) { id in
                VehicleDetailView(vehicleID: id)
            }
            .navigationDestination(for: RouteID.self) { id in
                RouteBuilderView(routeID: id)
            }
            .alert(
                "Purchase Failed",
                isPresented: Binding(get: { purchaseError != nil }, set: { if !$0 { purchaseError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Not enough cash for this vehicle.")
            }
            .sheet(item: $routeActionSelection) { selection in
                RouteCancellationSheet(routeID: selection.routeID, accent: accent)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
                    .presentationBackground(Theme.backgroundBottom)
            }
        }
        .tint(accent)
    }

    private var fleetModePicker: some View {
        HStack(spacing: 5) {
            ForEach(FleetMode.allCases, id: \.self) { item in
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

    @ViewBuilder private var routesContent: some View {
        if routes.isEmpty {
            Text("No routes yet. Build a custom route or assign a vehicle to a signed contract.")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfacePanel(cornerRadius: 18)
        } else {
            ForEach(routes) { route in
                RouteRow(
                    route: route,
                    accent: accent,
                    onOpen: { path.append(route.id) },
                    onRequestCancellation: {
                        routeActionSelection = RouteActionSelection(routeID: route.id)
                    }
                )
            }
        }

        Button {
            guard let routeID = session.createRoute() else { return }
            path.append(routeID)
        } label: {
            HStack(spacing: 7) {
                Text("+").font(.gg(15, .heavy)).foregroundStyle(accent)
                Text("Build a custom route")
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Theme.stroke.opacity(2))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var vehiclesContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(VehicleFilter.allCases, id: \.self) { filter in
                    let selected = vehicleFilter == filter
                    Button { vehicleFilter = filter } label: {
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

        let filtered = filteredVehicles
        if filtered.isEmpty {
            EmptyFleetCard()
        } else {
            ForEach(filtered) { vehicle in
                NavigationLink(value: vehicle.id) {
                    CompactFleetVehicleRow(vehicle: vehicle, accent: accent)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var filteredVehicles: [Vehicle] {
        switch vehicleFilter {
        case .all:
            return vehicles
        case .idle:
            guard let busy = session.state?.busyVehicleIDs() else { return vehicles }
            return vehicles.filter { !busy.contains($0.id) }
        case .onRoute:
            guard let busy = session.state?.busyVehicleIDs() else { return [] }
            return vehicles.filter { busy.contains($0.id) }
        }
    }

    private var shopContent: some View {
        VehicleShopInline(accent: accent, purchaseError: $purchaseError)
    }
}

// MARK: - Shared screen header

struct ScreenHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.gg(26, .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.gg(11.5, .heavy))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 44)
        .padding(.bottom, 10)
    }
}

/// A live route card: contract lane, its stops, serving vehicles and status.
private struct RouteRow: View {
    @Environment(GameSession.self) private var session
    let route: Route
    var accent: Color
    let onOpen: () -> Void
    let onRequestCancellation: () -> Void

    private var contract: ActiveContract? {
        route.contractID.flatMap { session.state?.activeContract($0) }
    }

    private var isCancelling: Bool { route.cancellationRequestedAt != nil }

    private var status: (text: String, color: Color) {
        if isCancelling {
            return (String(localized: "Cancelling"), Theme.warning)
        }
        if route.isRunning {
            return (String(localized: "Running"), Theme.mint)
        }
        return (String(localized: "Stopped"), Theme.textSecondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onOpen) {
                    HStack(spacing: 8) {
                        Text(route.name)
                            .font(.gg(14.5, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if route.contractID != nil {
                            TagPill(text: String(localized: "Contract"), color: Theme.brand)
                        }
                        TagPill(text: status.text, color: status.color)
                    }
                }
                .buttonStyle(.plain)

                Button(action: onRequestCancellation) {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isCancelling ? Theme.textTertiary : Theme.coral)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.coral.opacity(isCancelling ? 0.04 : 0.10)))
                }
                .buttonStyle(.plain)
                .disabled(isCancelling)
                .accessibilityLabel(isCancelling ? "Route cancellation in progress" : "Cancel or delete route")
            }

            VStack(alignment: .leading, spacing: 8) {
                // Stop list in lap order.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(route.stops.enumerated()), id: \.element.id) { index, stop in
                            if index > 0 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: stopSymbol(stop.task))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(stopColor(stop.task))
                                Text(session.catalog.city(stop.cityID)?.name ?? stop.cityID.rawValue)
                                    .font(.gg(11.5, .bold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }

                if route.vehicleIDs.isEmpty {
                    Text("No vehicle serving this route — shipments risk compensation.")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.coral)
                } else {
                    Text(vehicleSummary)
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }

                if let contract, let clock = session.state?.clock {
                    Text("\(contract.shipmentsCompleted) delivered · \(contract.shipmentsMissed) missed · next shipment in \(Format.duration(minutes: max(0, clock.minutes(until: contract.nextShipmentAt))))")
                        .font(.gg(11, .bold))
                        .foregroundStyle(contract.shipmentsMissed > 0 ? Theme.coral : Theme.textTertiary)
                }

                if route.contractID != nil && contract == nil {
                    Text("Contract ended — route is running empty.")
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.warning)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
        }
        .padding(14)
        .surfacePanel(cornerRadius: 16)
    }

    private var vehicleSummary: String {
        let codes = route.vehicleIDs.compactMap { id -> String? in
            guard let vehicle = session.state?.vehicle(id),
                  let type = session.catalog.vehicleType(vehicle.typeID) else { return nil }
            return Format.vehicleCode(typeName: type.name, id: vehicle.id)
        }
        return codes.joined(separator: " · ")
    }

    private func stopSymbol(_ task: RouteTask) -> String {
        switch task {
        case .travel: return "arrow.triangle.turn.up.right.circle"
        case .pickupShipment, .pickupContract: return "tray.and.arrow.up.fill"
        case .loadFromWarehouse: return "shippingbox.and.arrow.backward.fill"
        case .deliverShipment, .deliverContract, .deliverAll: return "tray.and.arrow.down.fill"
        case .dropToWarehouse: return "shippingbox.fill"
        }
    }

    private func stopColor(_ task: RouteTask) -> Color {
        switch task {
        case .travel: return Theme.textTertiary
        case .pickupShipment, .pickupContract, .loadFromWarehouse: return accent
        case .deliverShipment, .deliverContract, .deliverAll: return Theme.mint
        case .dropToWarehouse: return Theme.sky
        }
    }
}

private struct RouteCancellationSheet: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    var accent: Color
    @State private var commandError: CommandError?

    private var route: Route? { session.state?.route(routeID) }

    private var requiresWindDown: Bool {
        guard let state = session.state, let route else { return false }
        return route.isRunning || !state.routeRuns(of: route.id).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Theme.stroke.opacity(1.5))
                .frame(width: 44, height: 5)
                .padding(.top, 10)

            if let route {
                cancellationContent(route)
            } else {
                ContentUnavailableView(
                    "Route Unavailable",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    description: Text("This route was already removed.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.backgroundBottom)
        .tint(accent)
    }

    private func cancellationContent(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: requiresWindDown ? "stop.circle.fill" : "trash.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.coral)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.coral.opacity(0.10)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(requiresWindDown ? "Cancel route?" : "Delete route?")
                        .font(.gg(21, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(route.name)
                        .font(.gg(12.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if requiresWindDown {
                VStack(alignment: .leading, spacing: 10) {
                    consequenceRow(symbol: "shippingbox.fill", text: "New pickups stop immediately.")
                    consequenceRow(symbol: "truck.box.fill", text: "Loaded cargo finishes its delivery.")
                    consequenceRow(symbol: "parkingsign.circle.fill", text: "Vehicles release at the next safe city.")
                }
                .padding(14)
                .surfacePanel(cornerRadius: 16)
            } else {
                Text("The route is removed immediately. Assigned vehicles are released and remain in their current cities.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .surfacePanel(cornerRadius: 16)
            }

            if commandError != nil {
                Label("The route changed before it could be cancelled. Please try again.", systemImage: "exclamationmark.triangle.fill")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.coral)
            }

            Spacer(minLength: 0)

            VStack(spacing: 9) {
                Button {
                    if let error = session.perform(.deleteRoute(route.id)) {
                        commandError = error
                    } else {
                        dismiss()
                    }
                } label: {
                    Text(requiresWindDown ? "Cancel Route" : "Delete Route")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.coral))
                .disabled(route.cancellationRequestedAt != nil)
                .opacity(route.cancellationRequestedAt == nil ? 1 : 0.45)

                Button("Keep Route") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func consequenceRow(symbol: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 20)
            Text(text)
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}

private struct EmptyFleetCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No vehicles yet", systemImage: "truck.box")
                .font(.gg(15, .heavy))
                .foregroundStyle(Theme.brand)
            Text("Buy your first vehicle in the Shop tab to start hauling freight.")
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .surfacePanel()
    }
}

private struct CompactFleetVehicleRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    var accent: Color

    private var type: VehicleTypeDefinition? { session.catalog.vehicleType(vehicle.typeID) }

    var body: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            TagPill(text: statusText, color: statusColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .surfacePanel(cornerRadius: 16)
    }

    private var statusText: String {
        if session.state?.routeRun(for: vehicle.id) != nil { return String(localized: "On route") }
        if !vehicle.isAvailable { return String(localized: "On job") }
        if session.state?.route(of: vehicle.id) != nil { return String(localized: "Standby") }
        return String(localized: "Idle")
    }

    private var statusColor: Color {
        if session.state?.routeRun(for: vehicle.id) != nil { return Theme.mint }
        if !vehicle.isAvailable { return Theme.mint }
        if session.state?.route(of: vehicle.id) != nil { return Theme.sky }
        return Theme.textSecondary
    }

    private var code: String {
        Format.vehicleCode(typeName: type?.name ?? "VEH", id: vehicle.id)
    }

    private var subtitle: String {
        let typeName = type.map { String(localized: String.LocalizationValue($0.name)) } ?? "Vehicle"
        if vehicle.isAvailable {
            return "\(typeName) · \(session.catalog.city(vehicle.cityID)?.name ?? "")"
        }
        if let job = session.state?.activeJobs.first(where: { $0.vehicleID == vehicle.id }) {
            let from = session.catalog.city(job.offer.origin)?.name ?? ""
            let to = session.catalog.city(job.offer.destination)?.name ?? ""
            return "\(typeName) · \(from) → \(to)"
        }
        return typeName
    }
}

private struct VehicleShopInline: View {
    @Environment(GameSession.self) private var session
    var accent: Color
    @Binding var purchaseError: CommandError?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Vehicles")
            ForEach(session.catalog.vehicleTypes) { type in
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: String.LocalizationValue(type.name)))
                            .font(.gg(13.5, .heavy))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(Format.mass(kg: type.capacity.massKg)) · \(Int(type.speedKmh)) km/h")
                            .font(.gg(11, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        if let error = session.perform(.buyVehicle(type.id)) {
                            purchaseError = error
                        }
                    } label: {
                        Text(Format.money(type.purchasePrice))
                            .font(.gg(12.5, .heavy))
                            .foregroundStyle(Theme.onBrand)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(13)
                .surfacePanel(cornerRadius: 18)
            }

            SectionLabel("Add-ons")
            Text("Trailers and reefers unlock in a later update.")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfacePanel(cornerRadius: 18)
        }
    }
}

// MARK: - Vehicle detail (rich shell, design 1d)

struct VehicleDetailView: View {
    @Environment(GameSession.self) private var session
    let vehicleID: VehicleID

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }
    private var vehicle: Vehicle? { session.state?.vehicles.first { $0.id == vehicleID } }
    private var type: VehicleTypeDefinition? { vehicle.flatMap { session.catalog.vehicleType($0.typeID) } }
    private var job: ActiveJob? { session.state?.activeJobs.first { $0.vehicleID == vehicleID } }

    var body: some View {
        ScrollView {
            if let vehicle, let type {
                VStack(alignment: .leading, spacing: 14) {
                    header(vehicle: vehicle, type: type)
                    specCard(vehicle: vehicle, type: type)
                    addonsSection
                    assignedRouteSection
                    Color.clear.frame(height: Layout.tabBarClearance)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            } else {
                ContentUnavailableView("Vehicle Unavailable", systemImage: "truck.box")
                    .padding(.top, 80)
            }
        }
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(vehicle: Vehicle, type: VehicleTypeDefinition) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: String.LocalizationValue(type.name)))
                    .font(.gg(24, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(Int(type.speedKmh)) km/h • \(Format.distance(km: vehicle.odometerKm))")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            TagPill(text: status(for: vehicle).text, color: status(for: vehicle).color)
        }
        .padding(.top, 8)
    }

    private func specCard(vehicle: Vehicle, type: VehicleTypeDefinition) -> some View {
        VStack(spacing: 10) {
            TruckGlyph(accent: accent)

            let loadKg = job.map { _ in type.capacity.massKg } ?? 0
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                SpecTile(label: "Location",
                         value: job != nil
                            ? "\(session.catalog.city(job!.offer.origin)?.name ?? "") → \(session.catalog.city(job!.offer.destination)?.name ?? "")"
                            : (session.catalog.city(vehicle.cityID)?.name ?? "—"))
                SpecTile(label: "Driver", value: "Unassigned")
                SpecTile(label: "Load",
                         value: job != nil ? "\(Format.mass(kg: loadKg)) cap" : "Empty",
                         progress: job != nil ? 0.75 : 0, tint: accent)
                SpecTile(label: "Fuel", value: "Not tracked", progress: 0, tint: Theme.mint)
            }

            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption).foregroundStyle(accent)
                Text("Maintenance scheduling is coming soon.")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(accent.opacity(0.2), lineWidth: 1))
        }
        .padding(16)
        .surfacePanel(cornerRadius: 22)
    }

    private var addonsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Add-ons")
            HStack(spacing: 8) {
                addonPill(color: Theme.mint, text: "Dry cargo — fitted", strong: true)
                addonPill(color: Theme.sky, text: "Reefer — locked", strong: false)
            }
        }
    }

    private func addonPill(color: Color, text: String, strong: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.gg(12, strong ? .heavy : .bold))
                .foregroundStyle(strong ? Theme.textPrimary : Theme.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Capsule().fill(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(strong ? 0.12 : 0.06)))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

    private var assignedRouteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Assigned Route")
            if let route = session.state?.route(of: vehicleID) {
                NavigationLink {
                    RouteBuilderView(routeID: route.id)
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.title3).foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.name)
                                .font(.gg(13.5, .heavy)).foregroundStyle(Theme.textPrimary)
                            Text(route.contractID != nil
                                 ? "Contract route — shipments dispatch automatically"
                                 : "Custom route")
                                .font(.gg(11, .bold)).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .surfacePanel(cornerRadius: 18)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 11) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.title3).foregroundStyle(Theme.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job != nil ? "Active delivery" : "No route assigned")
                            .font(.gg(13.5, .heavy)).foregroundStyle(Theme.textPrimary)
                        Text("Assign this vehicle from a route builder.")
                            .font(.gg(11, .bold)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .padding(14)
                .surfacePanel(cornerRadius: 18)
            }
        }
    }

    private func status(for vehicle: Vehicle) -> (text: String, color: Color) {
        if session.state?.routeRun(for: vehicle.id) != nil {
            return (String(localized: "On route"), Theme.mint)
        }
        if !vehicle.isAvailable {
            return (String(localized: "On job"), Theme.mint)
        }
        if session.state?.route(of: vehicle.id) != nil {
            return (String(localized: "Standby"), Theme.sky)
        }
        return (String(localized: "Idle"), Theme.textSecondary)
    }
}

/// A single labelled spec tile with optional progress bar.
private struct SpecTile: View {
    let label: String
    let value: String
    var progress: Double? = nil
    var tint: Color = Theme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            Text(value)
                .font(.gg(13.5, .heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
            if let progress {
                ThemeProgressBar(value: progress, tint: tint, height: 5).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
    }
}

/// Stylized side-view truck badge used on the detail card.
private struct TruckGlyph: View {
    var accent: Color

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cab = CGRect(x: w * 0.64, y: h * 0.30, width: w * 0.22, height: h * 0.42)
            let box = CGRect(x: w * 0.06, y: h * 0.16, width: w * 0.56, height: h * 0.56)
            ctx.fill(Path(roundedRect: box, cornerRadius: 8), with: .color(Color(hex6: 0x1B3050)))
            ctx.stroke(Path(roundedRect: box, cornerRadius: 8), with: .color(Theme.stroke), lineWidth: 1.5)
            ctx.fill(Path(CGRect(x: box.minX, y: box.midY + 4, width: box.width, height: 8)), with: .color(accent.opacity(0.9)))
            ctx.fill(Path(roundedRect: cab, cornerRadius: 7), with: .color(accent))
            for fx in [0.16, 0.30, 0.52, 0.74] {
                let c = CGRect(x: w * fx - 9, y: h * 0.72, width: 18, height: 18)
                ctx.fill(Path(ellipseIn: c), with: .color(Color(hex6: 0x0A1220)))
                ctx.stroke(Path(ellipseIn: c), with: .color(Theme.stroke), lineWidth: 1.5)
            }
        }
        .frame(height: 84)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Vehicle shop

struct VehicleShopView: View {
    @Environment(GameSession.self) private var session
    var accent: Color
    @Binding var purchaseError: CommandError?
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(session.catalog.vehicleTypes) { vehicleType in
                        let affordable = (session.state?.cash ?? 0) >= vehicleType.purchasePrice
                        Button {
                            if let error = session.perform(.buyVehicle(vehicleType.id)) {
                                purchaseError = error
                            } else {
                                onClose()
                            }
                        } label: {
                            VehicleCard(vehicleType: vehicleType, isSelected: false, isAffordable: affordable, accent: accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(!affordable)
                    }
                }
                .padding(16)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationTitle("Vehicle Shop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onClose() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Image(systemName: "banknote").foregroundStyle(accent)
                    Text("Cash: \(Format.money(session.state?.cash ?? 0))")
                        .font(.gg(12.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.backgroundBottom.opacity(0.95).ignoresSafeArea(edges: .bottom))
            }
        }
        .tint(accent)
    }
}

// MARK: - Vehicle card (shop)

struct VehicleCard: View {
    let vehicleType: VehicleTypeDefinition
    let isSelected: Bool
    let isAffordable: Bool
    var accent: Color = Theme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: vehicleType.symbol)
                    .font(.title3)
                    .foregroundStyle(isAffordable ? accent : Theme.textSecondary)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: String.LocalizationValue(vehicleType.name)))
                        .font(.gg(16, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(Format.money(vehicleType.purchasePrice))
                        .font(.gg(13.5, .heavy))
                        .foregroundStyle(isAffordable ? Theme.brand : Theme.textSecondary)
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: isAffordable ? "plus.circle.fill" : "lock.fill")
                    .font(.title3)
                    .foregroundStyle(isAffordable ? accent : Theme.textSecondary)
            }
            HStack(spacing: 8) {
                StatChip(symbol: "scalemass", text: Format.mass(kg: vehicleType.capacity.massKg))
                StatChip(symbol: "cube", text: Format.volume(m3: vehicleType.capacity.volumeM3))
                StatChip(symbol: "speedometer", text: "\(Int(vehicleType.speedKmh)) km/h")
            }
        }
        .padding(16)
        .surfacePanel(selected: isSelected, accent: accent)
        .opacity(isAffordable ? 1 : 0.55)
    }
}
