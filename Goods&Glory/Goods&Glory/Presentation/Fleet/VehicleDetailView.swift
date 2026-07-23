//
//  VehicleDetailView.swift
//  Goods&Glory
//
//  One vehicle in full: specification, assignment and history.
//

import SwiftUI

struct VehicleDetailView: View {
    @Environment(GameSession.self) private var session
    private var accent: Color { session.accentColor }
    let vehicleID: VehicleID

    private var vehicle: Vehicle? { session.state?.vehicles.first { $0.id == vehicleID } }
    private var type: VehicleTypeDefinition? { vehicle.flatMap { session.catalog.vehicleType($0.typeID) } }

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

            let load = session.state?.cargoLoad(of: vehicle.id)
                ?? LoadSize(massKg: 0, volumeM3: 0)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                SpecTile(label: "Location",
                         value: location(of: vehicle))
                SpecTile(label: "Driver", value: "Unassigned")
                SpecTile(label: "Load",
                         value: load.massKg > 0 ? Format.mass(kg: load.massKg) : "Empty",
                         progress: load.fillRatio(in: type.capacity), tint: accent)
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
                            Text(!route.coveredLaneIDs.isEmpty
                                 ? "Serves a freight lane at the spot rate"
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
                        Text("No route assigned")
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
        let status = VehicleStatusDisplay.describe(vehicle, state: session.state)
        return (status.label, status.color)
    }

    private func location(of vehicle: Vehicle) -> String {
        guard let state = session.state,
              let run = state.routeRun(for: vehicle.id),
              run.phase == .traveling,
              let route = state.route(run.routeID),
              route.stops.indices.contains(run.stopIndex) else {
            return session.cityName(vehicle.cityID)
        }
        return "\(session.cityName(run.legOriginCityID)) → \(session.cityName(route.stops[run.stopIndex].cityID))"
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
