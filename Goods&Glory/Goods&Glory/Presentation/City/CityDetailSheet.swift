//
//  CityDetailSheet.swift
//  Goods&Glory
//
//  The city, opened as a sheet over the live map instead of a second screen.
//  The map behind stays the map and centers the city, so there is no back
//  button and no second Metal scene.
//
//  A pinned header answers "what kind of city is this" in icons; two tabs
//  keep the rest from becoming one long scroll.
//

import SwiftUI

enum CitySheetLayout {
    /// Sheet height as a share of the map. Matches the old detail panel's top
    /// edge, so the city still reads above it.
    static let detentFraction: CGFloat = 0.62
    static var detent: PresentationDetent { .fraction(detentFraction) }
}

enum CitySheetTab: String, CaseIterable, Identifiable {
    case city
    case jobs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .city: String(localized: "City")
        case .jobs: String(localized: "Jobs")
        }
    }

    var symbol: String {
        switch self {
        case .city: "building.2.fill"
        case .jobs: "shippingbox.fill"
        }
    }
}

struct CityDetailSheet: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID

    /// Jobs first: the player opens a city to dispatch, not to read.
    @State private var tab: CitySheetTab = .jobs

    private var accent: Color { session.accentColor }

    var body: some View {
        VStack(spacing: 0) {
            CityHeaderStrip(cityID: cityID)
                .padding(.horizontal, 16)
                .padding(.top, 6)

            tabBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider().overlay(Theme.stroke)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .city:
                        CityFacilitiesTab(cityID: cityID)
                    case .jobs:
                        CityJobsTab(cityID: cityID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.backgroundTop)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(CitySheetTab.allCases) { item in
                let isActive = tab == item
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .heavy))
                        Text(item.title)
                            .font(.gg(12.5, .heavy))
                    }
                    .foregroundStyle(isActive ? Theme.onBrand : Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isActive ? accent : Theme.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
