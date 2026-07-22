//
//  ParcelDetailView.swift
//  Goods&Glory
//
//  One parcel in full, with the vehicle choice that accepts it.
//

import SwiftUI

struct OfferDetailView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let offerID: JobID
    /// When shown under the floating game tab bar, leave scroll clearance.
    var clearsFloatingTabBar: Bool = true
    @State private var selectedVehicleID: VehicleID?
    @State private var commandError: CommandError?
    private var accent: Color { session.accentColor }

    private var offer: JobOffer? { session.state?.offers.first { $0.id == offerID } }

    var body: some View {
        ScrollView {
            if let offer {
                VStack(alignment: .leading, spacing: 14) {
                    offerDetails(offer)
                    vehiclePicker(offer)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            } else {
                ContentUnavailableView(
                    "Offer No Longer Available",
                    systemImage: "clock.badge.xmark",
                    description: Text("This offer expired or was taken.")
                )
                .padding(.top, 80)
            }
        }
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .navigationTitle("Parcel")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if offer != nil { acceptButton }
        }
        .alert(
            "Could Not Assign Job",
            isPresented: Binding(get: { commandError != nil }, set: { if !$0 { commandError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .tint(accent)
    }

    @ViewBuilder
    private func offerDetails(_ offer: JobOffer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(session.cityName(offer.origin)) → \(session.cityName(offer.destination))")
                .font(.gg(22, .heavy))
                .foregroundStyle(Theme.textPrimary)
            if let address = session.addressLine(from: offer.originFirmID, to: offer.destinationFirmID) {
                Text(address)
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let product = session.catalog.product(offer.productID) {
                    DetailTile(label: "Cargo", value: String(localized: String.LocalizationValue(product.name)), symbol: product.symbol)
                }
                DetailTile(label: "Load", value: "\(Format.mass(kg: offer.load.massKg)) · \(Format.volume(m3: offer.load.volumeM3))")
                DetailTile(label: "Distance", value: Format.distance(km: offer.distanceKm))
                DetailTile(label: "Payout", value: Format.money(offer.payout), tint: Theme.mint)
                DetailTile(label: "Rate", value: urgencyDetailLabel(offer.urgency))
                DetailTile(
                    label: "Source",
                    value: offer.source == .contract
                        ? String(localized: "Contract")
                        : String(localized: "Spot")
                )
                if let clock = session.state?.clock {
                    DetailTile(label: "Expires in", value: Format.duration(minutes: clock.minutes(until: offer.expiresAt)))
                }
            }
        }
        .padding(16)
        .surfacePanel(cornerRadius: 22)
    }

    @ViewBuilder
    private func vehiclePicker(_ offer: JobOffer) -> some View {
        let idleVehicles: [Vehicle] = {
            guard let state = session.state else { return [] }
            let busy = state.busyVehicleIDs()
            return state.vehicles.filter { !busy.contains($0.id) }
        }()
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Assign Vehicle")
            if idleVehicles.isEmpty {
                Text("No idle vehicles. Wait for a delivery to finish or buy a new vehicle.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surfacePanel()
            }
            ForEach(idleVehicles) { vehicle in
                let estimate = session.estimate(offer: offer, vehicle: vehicle)
                Button {
                    selectedVehicleID = vehicle.id
                } label: {
                    VehicleEstimateRow(vehicle: vehicle, estimate: estimate, isSelected: selectedVehicleID == vehicle.id, accent: accent)
                }
                .buttonStyle(.plain)
                .disabled(estimate == nil)
            }
        }
    }

    private var acceptButton: some View {
        Button {
            guard let selectedVehicleID else { return }
            if let error = session.perform(.acceptJob(offerID: offerID, vehicleID: selectedVehicleID)) {
                commandError = error
            } else {
                dismiss()
            }
        } label: {
            Text("Accept Job")
        }
        .buttonStyle(PrimaryButtonStyle(tint: accent))
        .disabled(selectedVehicleID == nil)
        .opacity(selectedVehicleID == nil ? 0.45 : 1)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, clearsFloatingTabBar ? Layout.tabBarClearance : 16)
        .background(Theme.backgroundBottom.opacity(0.92).ignoresSafeArea(edges: .bottom))
    }

    private var errorMessage: LocalizedStringKey {
        CommandErrorMessage.text(commandError)
    }

    private func urgencyDetailLabel(_ urgency: JobUrgency) -> String {
        switch urgency {
        case .economy: return String(localized: "Economy")
        case .normal: return String(localized: "Standard")
        case .urgent: return String(localized: "Urgent")
        }
    }

}

struct DetailTile: View {
    let label: String
    let value: String
    var symbol: String? = nil
    var tint: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(tint) }
                Text(value).font(.gg(14, .heavy)).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.18)))
    }
}

struct VehicleEstimateRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    let estimate: SimulationEngine.JobEstimate?
    let isSelected: Bool
    var accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let vehicleType = session.catalog.vehicleType(vehicle.typeID) {
                    Label(String(localized: String.LocalizationValue(vehicleType.name)), systemImage: vehicleType.symbol)
                        .font(.gg(14, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text("· \(session.catalog.city(vehicle.cityID)?.name ?? "")")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let route = session.state?.route(of: vehicle.id) {
                    TagPill(
                        text: route.coveredContractIDs.isEmpty
                            ? String(localized: "Route")
                            : String(localized: "Contract"),
                        color: route.coveredContractIDs.isEmpty ? Theme.sky : Theme.warning
                    )
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                }
            }
            if let estimate {
                HStack(spacing: 12) {
                    Text("Profit \(Format.money(estimate.estimatedProfit))")
                        .foregroundStyle(estimate.estimatedProfit >= 0 ? Theme.mint : Theme.coral)
                    Text(Format.duration(minutes: estimate.totalMinutes))
                        .foregroundStyle(Theme.textSecondary)
                    if estimate.deadheadKm > 0 {
                        Text("\(Format.distance(km: estimate.deadheadKm)) empty")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .font(.gg(11.5, .bold))
            } else {
                Text("Load does not fit this vehicle.")
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .padding(15)
        .surfacePanel(selected: isSelected, accent: accent)
        .contentShape(Rectangle())
    }
}
