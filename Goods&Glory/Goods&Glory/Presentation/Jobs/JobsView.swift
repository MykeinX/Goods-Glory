//
//  JobsView.swift
//  Goods&Glory
//
//  Operations tab. Persistent freight lanes are inspected per city on the map
//  — a global list is neither useful nor cheap.
//

import SwiftUI

struct JobsView: View {
    @Environment(GameSession.self) private var session
    private var accent: Color { session.accentColor }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Operations", trailing: "Reputation —/100")
                    .padding(.horizontal, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        OperationsNetworkView(accent: accent)
                        Color.clear.frame(height: Layout.tabBarClearance)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
        }
        .tint(accent)
    }
}
