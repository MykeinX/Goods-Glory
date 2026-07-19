//
//  FacilitiesView.swift
//  Goods&Glory
//
//  Facilities tab (design 2d): list of company buildings. Warehouse / garage
//  simulation is not wired yet — HQ is shown as the sole real entry and the
//  “build facility” CTA is a visual shell.
//

import SwiftUI

struct FacilitiesView: View {
    @Environment(GameSession.self) private var session

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            FacilitiesContent()
        }
        .tint(accent)
    }
}

/// Shared list content used by the Facilities tab and Company → Facilities.
struct FacilitiesContent: View {
    @Environment(GameSession.self) private var session

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    private var hqCityName: String? {
        guard let id = session.state?.config.hqCity else { return nil }
        return session.catalog.city(id)?.name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader(
                    title: "Facilities",
                    trailing: hqCityName.map { "HQ · \($0)" } ?? "No facilities yet"
                )

                if let hqID = session.state?.config.hqCity,
                   let hq = session.catalog.city(hqID) {
                    facilityRow(
                        title: "Headquarters",
                        city: hq.name,
                        detail: "Company base · no storage yet",
                        progress: 0.15,
                        tint: Color(hex6: 0x57B2FF),
                        symbol: "building.2.fill"
                    )
                }

                Button {
                    // Facility construction is a future simulation module.
                } label: {
                    HStack(spacing: 7) {
                        Text("+")
                            .font(.gg(15, .heavy))
                            .foregroundStyle(accent)
                        Text("Build facility — pick a city on the map")
                            .font(.gg(12.5, .heavy))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .foregroundStyle(Theme.stroke.opacity(2))
                    )
                }
                .buttonStyle(.plain)

                Color.clear.frame(height: Layout.tabBarClearance)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .background(Theme.backgroundBottom.ignoresSafeArea())
    }

    private func facilityRow(
        title: String,
        city: String,
        detail: String,
        progress: Double,
        tint: Color,
        symbol: String
    ) -> some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(title)
                        .font(.gg(13.5, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(city)
                        .font(.gg(10.5, .heavy))
                        .foregroundStyle(Theme.textTertiary)
                }
                ThemeProgressBar(value: progress, tint: tint, height: 5)
                    .padding(.vertical, 6)
                Text(detail)
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            Text("Detail →")
                .font(.gg(11.5, .heavy))
                .foregroundStyle(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .surfacePanel(cornerRadius: 18)
    }
}
