//
//  CityJobsTab.swift
//  Goods&Glory
//
//  Persistent freight lanes leaving this city.
//

import SwiftUI

struct CityJobsTab: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID

    private var accent: Color { session.accentColor }

    private var lanes: [FreightLane] { session.catalog.lanes(from: cityID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(String(localized: "Outbound lanes \(lanes.count)"))
            if lanes.isEmpty {
                emptyNote(String(localized: "No outbound freight lanes from this city."))
            } else {
                ForEach(lanes) { lane in
                    LaneRow(lane: lane, accent: accent)
                }
            }
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(.gg(12, .bold))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .surfacePanel(cornerRadius: 18)
    }
}
