//
//  GameView.swift
//  Goods&Glory
//
//  Main gameplay container. The design puts a full-bleed map behind a floating
//  glass tab bar (Map · Fleet · Jobs · Finance · Company). Time and money
//  controls live on the map overlay; each other tab owns its own header.
//

import SwiftUI

enum GameTab: Hashable, CaseIterable {
    case map, fleet, jobs, finance, company
}

/// Shared layout constants so scrolling tabs can clear the floating tab bar.
enum Layout {
    static let tabBarClearance: CGFloat = 96
}

struct GameView: View {
    @Environment(GameSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    // New campaigns open at the company HQ, where the CEO buys the first
    // vehicle and equipment before heading to the map.
    @State private var selectedTab: GameTab = .company

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.backgroundTop.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .map: MapTabView()
                case .fleet: FleetView()
                case .jobs: JobsView()
                case .finance: FinanceView()
                case .company: CompanyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            GameTabBar(selection: $selectedTab, accent: accent, jobsBadge: openOfferCount)
        }
        .background(Theme.backgroundTop)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                session.persist()
            }
        }
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
        .init(tab: .map, symbol: "map.fill", label: "Map"),
        .init(tab: .fleet, symbol: "truck.box.fill", label: "Fleet"),
        .init(tab: .jobs, symbol: "list.clipboard.fill", label: "Jobs"),
        .init(tab: .finance, symbol: "chart.bar.fill", label: "Finance"),
        .init(tab: .company, symbol: "building.2.fill", label: "Company")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.tab) { item in
                Button {
                    selection = item.tab
                } label: {
                    tabItem(item)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.surfaceGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func tabItem(_ item: Item) -> some View {
        let isActive = selection == item.tab
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(isActive ? accent : Theme.textTertiary)
                    .frame(width: 30, height: 24)
                if item.tab == .jobs && jobsBadge > 0 {
                    Text("\(min(jobsBadge, 99))")
                        .font(.gg(9, .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Circle().fill(Theme.coral))
                        .offset(x: 8, y: -4)
                }
            }
            Text(item.label)
                .font(.gg(9.5, .heavy))
                .foregroundStyle(isActive ? accent : Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}
