//
//  GameView.swift
//  Goods&Glory
//
//  Main gameplay container. Full-bleed content behind a floating glass tab bar:
//  Map · Fleet · Jobs · Facilities · Company (Finance lives under Company).
//

import SwiftUI

enum GameTab: Hashable, CaseIterable {
    case map, fleet, jobs, facilities, company
}

/// Shared layout constants so scrolling tabs can clear the floating tab bar.
enum Layout {
    /// Tab content (~49) + equal vertical padding + home-indicator cushion.
    static let tabBarClearance: CGFloat = 112
}

struct GameView: View {
    @Environment(GameSession.self) private var session
    @State private var selectedTab: GameTab = .map

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.backgroundTop.ignoresSafeArea()

            // Keep the live map mounted so pan/zoom survive leaving the Map tab.
            MapTabView()
                .opacity(selectedTab == .map ? 1 : 0)
                .allowsHitTesting(selectedTab == .map)
                .accessibilityHidden(selectedTab != .map)

            Group {
                switch selectedTab {
                case .map:
                    EmptyView()
                case .fleet:
                    FleetView()
                case .jobs:
                    JobsView()
                case .facilities:
                    FacilitiesView()
                case .company:
                    CompanyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GameTabBar(selection: $selectedTab, accent: accent, jobsBadge: openOfferCount)
        }
        .background(Theme.backgroundTop)
    }

    private var openOfferCount: Int {
        session.state?.offers.count ?? 0
    }
}

// MARK: - Floating tab bar

struct GameTabBar: View {
    @Binding var selection: GameTab
    var accent: Color
    var jobsBadge: Int

    private struct Item { let tab: GameTab; let symbol: String; let label: String }
    private let items: [Item] = [
        .init(tab: .map, symbol: "diamond.fill", label: "Map"),
        .init(tab: .fleet, symbol: "truck.box.fill", label: "Fleet"),
        .init(tab: .jobs, symbol: "list.bullet.rectangle.fill", label: "Jobs"),
        .init(tab: .facilities, symbol: "building.fill", label: "Facilities"),
        .init(tab: .company, symbol: "building.columns.fill", label: "Company")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(items, id: \.tab) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        tabItem(item)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Standard UITabBar content row (~49pt), equally padded so icons sit centered.
            .frame(height: 49)
            .padding(.top, 8)
            .padding(.bottom, 8)

            // Home-indicator cushion below the content row (not part of icon centering).
            Color.clear
                .frame(height: 16)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func tabItem(_ item: Item) -> some View {
        let isActive = selection == item.tab
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isActive ? accent : Theme.textTertiary)
                    .frame(width: 28, height: 24)
                if item.tab == .jobs && jobsBadge > 0 {
                    Text("\(min(jobsBadge, 99))")
                        .font(.gg(9.5, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Theme.coral))
                        .offset(x: 9, y: -5)
                }
            }
            Text(item.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? accent : Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}
