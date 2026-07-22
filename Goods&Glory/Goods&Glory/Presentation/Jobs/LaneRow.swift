//
//  LaneRow.swift
//  Goods&Glory
//
//  One persistent freight lane as a row: lane, firm, daily rate, what is
//  waiting at the dock, and the single action that matters — send a truck.
//

import SwiftUI

struct LaneRow: View {
    @Environment(GameSession.self) private var session
    let lane: FreightLane
    var accent: Color
    @State private var showsVehiclePicker = false

    private var waitingKg: Int { session.state?.laneAccrualKg[lane.id] ?? 0 }

    private var idleVehicles: [Vehicle] {
        guard let state = session.state else { return [] }
        return state.vehicles.filter {
            state.isVehicleIdle($0.id) && state.route(of: $0.id) == nil
        }
    }

    /// Vehicles already shuttling this lane (any route with its pickup task).
    private var servingVehicleCount: Int {
        guard let state = session.state else { return 0 }
        return state.routes
            .filter { route in
                route.stops.contains { $0.task == .pickupLane(lane.id) }
            }
            .reduce(0) { $0 + $1.vehicleIDs.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(accent.opacity(0.14))
                        .frame(width: 34, height: 34)
                    Image(systemName: session.catalog.product(lane.productID)?.symbol
                          ?? "shippingbox.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(session.cityName(lane.originCityID)) → \(session.cityName(lane.destinationCityID))")
                        .font(.gg(13.5, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(session.catalog.firm(lane.originFirmID)?.name ?? "")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("~\(Format.mass(kg: lane.baseRatePerDayKg))/day")
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                    Text(waitingKg > 0
                         ? "\(Format.mass(kg: waitingKg)) waiting"
                         : String(localized: "Dock clear"))
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(waitingKg > 0 ? accent : Theme.textTertiary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                if servingVehicleCount > 0 {
                    TagPill(
                        text: String(localized: "\(servingVehicleCount) serving"),
                        color: Theme.mint
                    )
                }
                Spacer(minLength: 4)
                Button {
                    showsVehiclePicker = true
                } label: {
                    Text("Send truck")
                        .font(.gg(12, .heavy))
                        .foregroundStyle(idleVehicles.isEmpty ? Theme.textTertiary : Theme.onBrand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(idleVehicles.isEmpty ? Theme.surface : accent))
                }
                .buttonStyle(.plain)
                .disabled(idleVehicles.isEmpty)
            }
        }
        .padding(13)
        .surfacePanel(cornerRadius: 16)
        .confirmationDialog(
            "Send which truck?",
            isPresented: $showsVehiclePicker,
            titleVisibility: .visible
        ) {
            ForEach(idleVehicles) { vehicle in
                let typeName = session.catalog.vehicleType(vehicle.typeID)?.name ?? "Vehicle"
                Button("\(Format.vehicleCode(typeName: typeName, id: vehicle.id)) — \(session.cityName(vehicle.cityID))") {
                    session.perform(.dispatchVehicleToLane(laneID: lane.id, vehicleID: vehicle.id))
                }
            }
        } message: {
            Text("The truck shuttles this lane at the spot rate until you stop its route.")
        }
    }

}

