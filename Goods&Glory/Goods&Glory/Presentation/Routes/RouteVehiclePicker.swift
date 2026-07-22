//
//  RouteVehiclePicker.swift
//  Goods&Glory
//
//  Assigning vehicles to a lane.
//

import SwiftUI

struct RouteVehiclePicker: View {
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
        let busy = state.busyVehicleIDs()
        let routed = state.routedVehicleIDs()
        return state.vehicles
            .filter { !busy.contains($0.id) && !routed.contains($0.id) }
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
                    Text(session.vehicleCode(vehicle))
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

}

