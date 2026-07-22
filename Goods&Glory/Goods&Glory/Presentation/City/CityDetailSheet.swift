//
//  CityDetailSheet.swift
//  Goods&Glory
//
//  The city, opened as a sheet over the live map instead of a second screen.
//  The map behind stays the map — it centers the city and keeps drawing the
//  parcel preview arc, so there is no back button and no second Metal scene.
//
//  A pinned header answers "what kind of city is this" in icons; three tabs
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
    case contracts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .city: String(localized: "City")
        case .jobs: String(localized: "Jobs")
        case .contracts: String(localized: "Contracts")
        }
    }

    var symbol: String {
        switch self {
        case .city: "building.2.fill"
        case .jobs: "shippingbox.fill"
        case .contracts: "doc.text.fill"
        }
    }
}

struct CityDetailSheet: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID
    /// Parcel the player is inspecting — drives the arc drawn on the map below.
    @Binding var previewOfferID: JobID?

    /// Jobs first: the player opens a city to dispatch, not to read.
    @State private var tab: CitySheetTab = .jobs

    private var accent: Color { session.accentColor }

    private var waitingJobCount: Int {
        (session.state?.offers ?? []).count { $0.origin == cityID }
    }

    private var contractOfferCount: Int {
        guard let state = session.state, state.hasOperationalOffice(in: cityID) else { return 0 }
        return state.contractOffers.count { $0.origin == cityID }
    }

    private func badge(for tab: CitySheetTab) -> Int {
        switch tab {
        case .city: 0
        case .jobs: waitingJobCount
        case .contracts: contractOfferCount
        }
    }

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
                        CityJobsTab(cityID: cityID, previewOfferID: $previewOfferID)
                    case .contracts:
                        CityContractsTab(cityID: cityID)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.backgroundTop)
        .onChange(of: cityID) { _, _ in previewOfferID = nil }
        .onChange(of: tab) { _, newValue in
            // The arc belongs to a parcel; leaving the jobs tab drops it.
            if newValue != .jobs { previewOfferID = nil }
        }
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
                        let count = badge(for: item)
                        if count > 0 {
                            Text("\(count)")
                                .font(.gg(10, .heavy))
                                .monospacedDigit()
                                .foregroundStyle(isActive ? Theme.onBrand : accent)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(
                                        isActive
                                            ? Theme.onBrand.opacity(0.22)
                                            : accent.opacity(0.16)
                                    )
                                )
                        }
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
