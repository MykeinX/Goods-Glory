//
//  JobsView.swift
//  Goods&Glory
//
//  Operations tab: Active work and Contracts. Persistent freight lanes are
//  inspected per city on the map — a global list is neither useful nor cheap.
//

import SwiftUI

/// One level of navigation: live work vs contract market.
private enum JobsMode: CaseIterable {
    case active, contracts
    var title: String {
        switch self {
        case .active: return "Active"
        case .contracts: return "Contracts"
        }
    }
}

struct JobsView: View {
    @Environment(GameSession.self) private var session
    @State private var mode: JobsMode = .active
    private var accent: Color { session.accentColor }


    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Operations", trailing: "Reputation —/100")
                    .padding(.horizontal, 14)

                jobsModePicker
                    .padding(.horizontal, 14)
                    .padding(.top, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        switch mode {
                        case .active: OperationsNetworkView(accent: accent)
                        case .contracts: ContractMarketList(accent: accent)
                        }
                        Color.clear.frame(height: Layout.tabBarClearance)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationDestination(for: JobID.self) { offerID in
                OfferDetailView(offerID: offerID)
            }
        }
        .tint(accent)
    }

    private var jobsModePicker: some View {
        HStack(spacing: 5) {
            ForEach(JobsMode.allCases, id: \.self) { item in
                let isActive = mode == item
                Button { mode = item } label: {
                    Text(item.title)
                        .font(.gg(13, .heavy))
                        .foregroundStyle(isActive ? Theme.onBrand : Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(isActive ? accent : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
    }

}
