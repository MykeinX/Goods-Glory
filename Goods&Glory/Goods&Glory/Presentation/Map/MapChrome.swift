//
//  MapChrome.swift
//  Goods&Glory
//
//  Persistent map furniture: the status bar, speed control, bottom chrome
//  and the fleet chips. Everything that frames the map without being it.
//

import SwiftUI

struct MapStatusOverlay: View {
    @Environment(GameSession.self) private var session
    var accent: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if let identity = session.state?.config.identity {
                    HStack(spacing: 8) {
                        Text(identity.name.prefix(1).uppercased())
                            .font(.gg(11, .heavy))
                            .foregroundStyle(Theme.onBrand)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent))
                        Text(identity.name)
                            .font(.gg(12.5, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .glassPill()
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Text(Format.money(session.state?.cash ?? 0))
                        .font(.gg(15, .heavy))
                        .foregroundStyle(Theme.mint)
                        .monospacedDigit()
                }
                .glassPill()
            }

            HStack {
                if let clock = session.state?.clock {
                    Text(Format.gameTime(clock))
                        .font(.gg(11.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                        .glassPill()
                }
                Spacer(minLength: 8)
                GameSpeedControl(accent: accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}

/// The paused / 1× / 3× / 6× time control.
struct GameSpeedControl: View {
    @Environment(GameSession.self) private var session
    var accent: Color

    private struct Speed { let value: SimulationSpeed; let label: String; let symbol: String? }
    private let speeds: [Speed] = [
        .init(value: .paused, label: "", symbol: "pause.fill"),
        .init(value: .normal, label: "1×", symbol: nil),
        .init(value: .fast, label: "3×", symbol: nil),
        .init(value: .veryFast, label: "6×", symbol: nil)
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(speeds, id: \.value) { speed in
                let isActive = session.speed == speed.value
                Button {
                    session.speed = speed.value
                } label: {
                    Group {
                        if let symbol = speed.symbol {
                            Image(systemName: symbol).font(.system(size: 11, weight: .heavy))
                        } else {
                            Text(speed.label).font(.gg(12, .heavy))
                        }
                    }
                    .foregroundStyle(isActive ? Theme.onBrand : Theme.textSecondary)
                    .frame(minWidth: 34, minHeight: 30)
                    .background(Capsule().fill(isActive ? accent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Theme.surfaceGlass))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

private extension View {
    func glassPill() -> some View {
        self
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(Capsule().fill(Theme.surfaceGlass))
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Bottom chrome (popup + fleet summary)

struct MapBottomChrome: View {
    @Environment(GameSession.self) private var session
    var accent: Color
    @Binding var selection: MapSelection
    var onOpenDetail: (MapDetailDestination) -> Void
    var onFocusCity: (CityID) -> Void

    /// Both counts from one pass. Computed together because this runs on every
    /// simulation tick, and the previous per-vehicle `isVehicleIdle` calls made
    /// it two full rescans of the job and run lists.
    private var fleetSplit: (onRoute: Int, idle: Int) {
        guard let state = session.state else { return (0, 0) }
        let busy = state.busyVehicleIDs()
        let onRoute = state.vehicles.count { busy.contains($0.id) }
        return (onRoute, state.vehicles.count - onRoute)
    }

    var body: some View {
        let fleet = fleetSplit
        return VStack(spacing: 10) {
            GameNotificationStack(
                notifications: session.notifications,
                accent: accent,
                onTap: { note in
                    guard let cityID = note.mapFocusCityID else { return }
                    onFocusCity(cityID)
                }
            )
                .padding(.horizontal, 14)

            switch selection {
            // A tapped city opens the city sheet instead of a card here.
            case .none, .city:
                EmptyView()
            case .vehicle(let id):
                MapVehiclePopup(
                    vehicleID: id,
                    accent: accent,
                    onClose: { selection = .none },
                    onOpenDetail: { onOpenDetail(.vehicle(id)) }
                )
                .padding(.horizontal, 14)
            }

            HStack(spacing: 8) {
                MapFleetStatChip(
                    systemImage: "truck.box.fill",
                    tint: accent,
                    count: fleet.onRoute,
                    label: String(localized: "on route")
                )
                MapFleetStatChip(
                    systemImage: "truck.box",
                    tint: Theme.textSecondary,
                    count: fleet.idle,
                    label: String(localized: "idle")
                )
            }
            .padding(.horizontal, 14)
        }
        // Sit the fleet chips closer to the tab bar (was floating too high).
        .padding(.bottom, Layout.tabBarClearance - 12)
    }
}

// MARK: - Session notifications (log-backed toasts)

struct MapFleetStatChip: View {
    let systemImage: String
    let tint: Color
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            HStack(spacing: 4) {
                Text("\(count)")
                    .font(.gg(14, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
                Text(label)
                    .font(.gg(11.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Selection popups

