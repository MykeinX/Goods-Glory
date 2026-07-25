//
//  MapLoadTestControls.swift
//  Goods&Glory
//
//  Developer-only: put a large fleet on the map and read the render budget off
//  the HUD above it. Rides along with the performance overlay, so it appears
//  and disappears with the same setting. Compiled out of release builds.
//

#if DEBUG

import SwiftUI

struct MapLoadTestControls: View {
    let session: GameSession

    private static let sizes = [100, 300, 600]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.sizes, id: \.self) { size in
                Button("+\(size)") {
                    session.seedLoadTestFleet(count: size)
                }
                .buttonStyle(LoadTestButtonStyle(tint: .orange))
            }
            Button("clear") {
                session.clearLoadTestFleet()
            }
            .buttonStyle(LoadTestButtonStyle(tint: .red))
        }
    }
}

private struct LoadTestButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(tint.opacity(0.45), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

#endif
