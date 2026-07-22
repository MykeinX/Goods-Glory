//
//  RouteCancellationSheet.swift
//  Goods&Glory
//
//  Stopping or deleting a route, with the wind-down rules stated plainly.
//
//  This existed twice — once in Fleet, once in the route builder — under the
//  same name, with different logic and different copy. Two answers to "what
//  happens to my cargo?" is worse than either answer alone.
//

import SwiftUI

struct RouteCancellationSheet: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    var accent: Color
    /// Called after the request lands, so a caller that is *inside* the route
    /// being deleted can dismiss itself.
    var onRequested: (() -> Void)? = nil

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
                        onRequested?()
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

