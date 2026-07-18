//
//  CompanyView.swift
//  Goods&Glory
//
//  Company tab: the company's identity, headquarters, a compact performance
//  summary and the activity logbook. Fleet and finance now live in their own
//  tabs; this screen is the "who we are" home and the save/exit point.
//

import SwiftUI

struct CompanyView: View {
    @Environment(GameSession.self) private var session
    @State private var showsExitConfirm = false

    private var accent: Color {
        Color(hex: session.state?.config.identity.colorHex ?? "#FFB037")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    identityCard
                    summaryRow
                    logbookSection
                    exitButton
                    Color.clear.frame(height: Layout.tabBarClearance)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
        }
        .tint(accent)
    }

    private var header: some View {
        HStack {
            Text("Company")
                .font(.gg(28, .heavy))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.top, 44)
    }

    private var identityCard: some View {
        HStack(spacing: 14) {
            if let identity = session.state?.config.identity {
                CompanyMark(emblemSymbol: identity.emblemSymbol, color: accent, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.name)
                        .font(.gg(19, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    if let hqID = session.state?.config.hqCity,
                       let hq = session.catalog.city(hqID) {
                        Text("HQ · \(hq.name)")
                            .font(.gg(12.5, .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer()
        }
        .padding(16)
        .surfacePanel(cornerRadius: 22)
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            summaryTile(label: "Cash", value: Format.money(session.state?.cash ?? 0), tint: Theme.mint)
            summaryTile(label: "Deliveries", value: (session.state?.stats.deliveredJobs ?? 0).formatted(), tint: Theme.textPrimary)
            summaryTile(label: "Fleet", value: (session.state?.vehicles.count ?? 0).formatted(), tint: Theme.textPrimary)
        }
    }

    private func summaryTile(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            Text(value)
                .font(.gg(17, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .surfacePanel()
    }

    private var logbookSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Activity")
            let entries = Array((session.state?.log ?? []).suffix(20).reversed())
            if entries.isEmpty {
                Text("Your company's story starts here.")
                    .font(.gg(12.5, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .surfacePanel()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.message(catalog: session.catalog))
                                .font(.gg(13, .bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(Format.gameTime(entry.at))
                                .font(.gg(10.5, .bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        if index < entries.count - 1 {
                            Rectangle().fill(Theme.strokeSoft).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .surfacePanel()
            }
        }
    }

    private var exitButton: some View {
        Button {
            showsExitConfirm = true
        } label: {
            Label("Save & Exit to Menu", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .buttonStyle(SecondaryButtonStyle())
        .padding(.top, 2)
        .confirmationDialog("Save and return to the main menu?", isPresented: $showsExitConfirm, titleVisibility: .visible) {
            Button("Save & Exit") { session.quitToMenu() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
