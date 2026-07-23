//
//  FleetView.swift
//  Goods&Glory
//
//  Fleet tab (design 3b): Routes / Vehicles / Shop segments, all three on live
//  state. Cancelling a lane lives in the route screen, not in this list — it is
//  too expensive to rebuild to sit one stray tap from a delete control.
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

struct FleetView: View {
    @Environment(GameSession.self) private var session
    @State private var path = NavigationPath()
    @State private var mode: FleetMode = .vehicles
    @State private var vehicleFilter: VehicleFilter = .all
    @State private var purchaseError: CommandError?
    private var accent: Color { session.accentColor }


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
            Text("No routes yet. Build a route to start serving freight lanes.")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfacePanel(cornerRadius: 18)
        } else {
            ForEach(routes) { route in
                RouteRow(route: route, accent: accent, onOpen: { path.append(route.id) })
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
