//
//  MapVehiclePopup.swift
//  Goods&Glory
//
//  The card that opens when a vehicle is tapped: what it carries, where it
//  is going, and how its lap is progressing.
//

import SwiftUI

struct MapVehiclePopup: View {
    @Environment(GameSession.self) private var session
    let vehicleID: VehicleID
    var accent: Color
    var onClose: () -> Void
    var onOpenDetail: () -> Void

    private var vehicle: Vehicle? {
        session.state?.vehicles.first { $0.id == vehicleID }
    }
    private var type: VehicleTypeDefinition? {
        vehicle.flatMap { session.catalog.vehicleType($0.typeID) }
    }
    private var run: RouteRun? {
        session.state?.routeRun(for: vehicleID)
    }
    private var route: Route? {
        guard let run else { return nil }
        return session.state?.route(run.routeID)
    }
    private var currentStop: RouteStop? {
        guard let run, let route, route.stops.indices.contains(run.stopIndex) else { return nil }
        return route.stops[run.stopIndex]
    }
    private var isActive: Bool { run != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Text(code)
                    .font(.gg(16, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                TagPill(
                    text: statusTag,
                    color: isActive ? Theme.mint : Theme.textSecondary
                )
                Spacer(minLength: 8)
                closeButton(action: onClose)
            }

            Text(subtitle)
                .font(.gg(12.5, .bold))
                .foregroundStyle(Theme.textSecondary)

            chipRow(chips)

            detailCTA(
                title: String(localized: "Go to vehicle detail →"),
                border: accent.opacity(0.35),
                action: onOpenDetail
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1.5)
        )
    }

    private var code: String {
        Format.vehicleCode(typeName: type?.name ?? "VEH", id: vehicleID)
    }

    private var statusTag: String {
        if let run {
            switch run.phase {
            case .traveling: return String(localized: "On route")
            case .servicing: return serviceStatus
            case .waiting: return String(localized: "Waiting")
            }
        }
        return String(localized: "Idle")
    }

    private var subtitle: String {
        guard let vehicle else { return String(localized: "Vehicle unavailable") }
        if let run, let stop = currentStop {
            let from = session.catalog.city(run.legOriginCityID)?.name ?? run.legOriginCityID.rawValue
            let to = session.catalog.city(stop.cityID)?.name ?? stop.cityID.rawValue
            switch run.phase {
            case .traveling:
                let eta = remainingTime(until: run.phaseEndsAt)
                return "\(from) → \(to) · \(eta) left"
            case .servicing:
                let eta = remainingTime(until: run.phaseEndsAt)
                return "\(serviceStatus) in \(to) · \(eta) left"
            case .waiting:
                return String(localized: "Waiting in \(to)")
            }
        }
        let city = session.catalog.city(vehicle.cityID)?.name ?? ""
        return String(localized: "Waiting in \(city)")
    }

    private var chips: [MapPopupChip] {
        var items: [MapPopupChip] = []
        if let type {
            items.append(.init(
                text: String(localized: String.LocalizationValue(type.name)),
                emphasized: false
            ))
        }
        if run != nil {
            if let route {
                items.append(.init(text: route.name, emphasized: true))
            }
            if let state = session.state {
                let load = state.cargoLoad(of: vehicleID)
                if load.massKg > 0 {
                    items.append(.init(text: Format.mass(kg: load.massKg), emphasized: true))
                    if let type {
                        let fill = load.fillRatio(in: type.capacity)
                        let percent = Int((fill * 100).rounded())
                        items.append(.init(
                            text: String(localized: "\(percent)% full"),
                            emphasized: false
                        ))
                    }
                } else {
                    items.append(.init(text: String(localized: "Empty"), emphasized: false))
                }
            }
        } else {
            items.append(.init(text: String(localized: "Find a return load"), emphasized: true))
        }
        return items
    }

    private var serviceStatus: String {
        currentStop?.task.activityLabel ?? String(localized: "Servicing")
    }

    private func remainingTime(until end: GameTime) -> String {
        guard let clock = session.state?.clock else { return Format.duration(minutes: 0) }
        return Format.duration(minutes: max(0, clock.minutes(until: end)))
    }

}
