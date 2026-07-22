//
//  GameNotificationStack.swift
//  Goods&Glory
//
//  Transient toasts derived from the campaign log.
//

import SwiftUI

struct GameNotificationStack: View {
    let notifications: [GameNotification]
    var accent: Color
    var onTap: (GameNotification) -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(notifications) { note in
                GameNotificationBanner(notification: note, accent: accent) {
                    onTap(note)
                }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: notifications)
    }
}

struct GameNotificationBanner: View {
    let notification: GameNotification
    var accent: Color
    var onTap: () -> Void

    private var tint: Color {
        switch notification.chrome {
        case .brand: return accent
        case .success: return Theme.mint
        case .warning: return Theme.coral
        }
    }

    private var isTappable: Bool { notification.mapFocusCityID != nil }

    var body: some View {
        let content = HStack(spacing: 10) {
            Image(systemName: notification.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.gg(12.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(notification.detail)
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        if isTappable {
            Button(action: onTap) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityHint(String(localized: "Shows this city on the map"))
        } else {
            content
        }
    }
}

