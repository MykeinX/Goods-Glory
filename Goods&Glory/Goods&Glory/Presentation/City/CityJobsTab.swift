//
//  CityJobsTab.swift
//  Goods&Glory
//
//  Everything leaving this city that needs a truck. Contract obligations and
//  spot parcels used to be two lists showing the same offers — they are one
//  list here, sorted by the only thing that ranks them: time left.
//

import SwiftUI

struct CityJobsTab: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID
    @Binding var previewOfferID: JobID?

    @State private var commandError: CommandError?

    private var accent: Color { session.accentColor }

    private var waitingOffers: [JobOffer] {
        (session.state?.offers ?? [])
            .filter { $0.origin == cityID }
            .sorted { $0.expiresAt < $1.expiresAt }
    }

    private var lanes: [FreightLane] { session.catalog.lanes(from: cityID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(String(localized: "Waiting parcels \(waitingOffers.count)"))

            if waitingOffers.isEmpty {
                emptyNote(String(
                    localized: "Nothing is booked out of here right now. Lanes below still build up at the docks."
                ))
            } else {
                ForEach(waitingOffers) { offer in
                    CityJobCard(
                        offer: offer,
                        previewOfferID: $previewOfferID,
                        onError: { commandError = $0 }
                    )
                }
            }

            if !lanes.isEmpty {
                SectionLabel(String(localized: "Outbound lanes \(lanes.count)"))
                    .padding(.top, 6)
                ForEach(lanes) { lane in
                    LaneRow(lane: lane, accent: accent)
                }
            }
        }
        .alert(
            "Could Not Assign Job",
            isPresented: Binding(
                get: { commandError != nil },
                set: { if !$0 { commandError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CommandErrorMessage.text(commandError))
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
