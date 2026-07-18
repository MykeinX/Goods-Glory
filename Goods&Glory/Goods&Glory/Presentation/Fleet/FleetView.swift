//
//  FleetView.swift
//  Goods&Glory
//
//  Fleet tab (design 1d): the company's vehicles as cards, a vehicle detail
//  screen and a route-builder preview. Real data (type, capacity, location,
//  odometer, assigned job) drives the screen; driver / fuel / maintenance /
//  add-ons and the multi-stop route builder are visual shells for features that
//  do not have a simulation backend yet.
//

import SwiftUI

struct FleetView: View {
    @Environment(GameSession.self) private var session
    @State private var showsShop = false
    @State private var purchaseError: CommandError?

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "Fleet", trailing: "\(session.state?.vehicles.count ?? 0) vehicles")

                    let vehicles = session.state?.vehicles ?? []
                    if vehicles.isEmpty {
                        EmptyFleetCard()
                    } else {
                        ForEach(vehicles) { vehicle in
                            NavigationLink(value: vehicle.id) {
                                FleetVehicleCard(vehicle: vehicle, accent: accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        showsShop = true
                    } label: {
                        Label("Buy Vehicle", systemImage: "plus")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: accent))
                    .padding(.top, 2)

                    Color.clear.frame(height: Layout.tabBarClearance)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationDestination(for: VehicleID.self) { id in
                VehicleDetailView(vehicleID: id)
            }
            .sheet(isPresented: $showsShop) {
                VehicleShopView(accent: accent, purchaseError: $purchaseError, onClose: { showsShop = false })
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
}

// MARK: - Shared screen header

struct ScreenHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.gg(28, .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, 44)
    }
}

private struct EmptyFleetCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No vehicles yet", systemImage: "truck.box")
                .font(.gg(15, .heavy))
                .foregroundStyle(Theme.brand)
            Text("Buy your first vehicle to start hauling freight.")
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .surfacePanel()
    }
}

// MARK: - Vehicle list card

private struct FleetVehicleCard: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle
    var accent: Color

    private var type: VehicleTypeDefinition? { session.catalog.vehicleType(vehicle.typeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: type?.symbol ?? "truck.box.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedName)
                        .font(.gg(16, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                statusTag
            }
            if let type {
                HStack(spacing: 8) {
                    StatChip(symbol: "scalemass", text: Format.mass(kg: type.capacity.massKg))
                    StatChip(symbol: "cube", text: Format.volume(m3: type.capacity.volumeM3))
                    StatChip(symbol: "gauge.with.dots.needle.bottom.50percent", text: Format.distance(km: vehicle.odometerKm))
                }
            }
        }
        .padding(15)
        .surfacePanel()
    }

    private var localizedName: String {
        guard let type else { return "Vehicle" }
        return String(localized: String.LocalizationValue(type.name))
    }

    private var subtitle: String {
        if vehicle.isAvailable {
            return "Idle · \(session.catalog.city(vehicle.cityID)?.name ?? "")"
        } else if let job = session.state?.activeJobs.first(where: { $0.vehicleID == vehicle.id }) {
            return "\(session.catalog.city(job.offer.origin)?.name ?? "") → \(session.catalog.city(job.offer.destination)?.name ?? "")"
        }
        return "On the job"
    }

    @ViewBuilder private var statusTag: some View {
        if vehicle.isAvailable {
            TagPill(text: "Idle", color: Theme.textSecondary)
        } else {
            TagPill(text: "On route", color: Theme.mint)
        }
    }
}

// MARK: - Vehicle detail (rich shell, design 1d)

struct VehicleDetailView: View {
    @Environment(GameSession.self) private var session
    let vehicleID: VehicleID
    @State private var showsRouteBuilder = false

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
        .sheet(isPresented: $showsRouteBuilder) {
            RouteBuilderView(accent: accent)
        }
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
            TagPill(text: vehicle.isAvailable ? "Idle" : "On route",
                    color: vehicle.isAvailable ? Theme.textSecondary : Theme.mint)
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
            Button { showsRouteBuilder = true } label: {
                HStack(spacing: 11) {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.title3).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job != nil ? "Active delivery" : "No route assigned")
                            .font(.gg(13.5, .heavy)).foregroundStyle(Theme.textPrimary)
                        Text("Open the route builder")
                            .font(.gg(11, .bold)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("Edit →").font(.gg(12, .heavy)).foregroundStyle(accent)
                }
                .padding(14)
                .surfacePanel(cornerRadius: 18)
            }
            .buttonStyle(.plain)
        }
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

// MARK: - Route builder (preview shell, design 1c)

struct RouteBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    var accent: Color

    private struct Step { let n: Int; let title: String; let sub: String; let type: String; let color: Color }
    private let steps: [Step] = [
        .init(n: 1, title: "Pickup", sub: "Load freight at origin", type: "PICKUP", color: Theme.brand),
        .init(n: 2, title: "Transfer", sub: "Consolidate at a hub", type: "TRANSFER", color: Theme.sky),
        .init(n: 3, title: "Deliver", sub: "Drop at destination", type: "DELIVER", color: Theme.mint),
        .init(n: 4, title: "Return load", sub: "Fill the empty leg", type: "SPOT", color: Theme.coral),
        .init(n: 5, title: "Loop", sub: "Repeat the route", type: "LOOP", color: Theme.violet)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill").font(.caption).foregroundStyle(accent)
                        Text("Preview — multi-stop routes & loops arrive in a later update.")
                            .font(.gg(11.5, .bold)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(accent.opacity(0.08)))

                    ForEach(steps, id: \.n) { step in
                        HStack(spacing: 11) {
                            Text("\(step.n)")
                                .font(.gg(13, .heavy)).foregroundStyle(Theme.onBrand)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(step.color))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(step.title).font(.gg(13.5, .heavy)).foregroundStyle(Theme.textPrimary)
                                Text(step.sub).font(.gg(11, .bold)).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            TagPill(text: step.type, color: step.color)
                        }
                        .padding(12)
                        .surfacePanel(cornerRadius: 16)
                    }

                    HStack(spacing: 7) {
                        Image(systemName: "plus").font(.headline).foregroundStyle(accent)
                        Text("Add step — tap a point on the map")
                            .font(.gg(12.5, .heavy)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    )
                }
                .padding(16)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationTitle("Route Builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .tint(accent)
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
