//
//  CompanyView.swift
//  Goods&Glory
//
//  Company hub (design 2e): identity, reputation placeholder, performance
//  tiles and links into Finance / Facilities / Personnel / Contracts.
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
                VStack(alignment: .leading, spacing: 12) {
                    identityHeader
                    reputationCard
                    statsGrid
                    linkRows
                    exitButton
                    Color.clear.frame(height: Layout.tabBarClearance)
                }
                .padding(.horizontal, 14)
                .padding(.top, 52)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationDestination(for: CompanyDestination.self) { destination in
                switch destination {
                case .finance:
                    FinanceView()
                case .facilities:
                    FacilitiesContent()
                        .navigationTitle("Facilities")
                        .navigationBarTitleDisplayMode(.inline)
                case .personnel, .contracts:
                    ComingSoonDetail(
                        title: destination.title,
                        message: destination.placeholder
                    )
                }
            }
        }
        .tint(accent)
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            if let identity = session.state?.config.identity {
                CompanyMark(emblemSymbol: identity.emblemSymbol, color: accent, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.name)
                        .font(.gg(22, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitleLine)
                        .font(.gg(11.5, .heavy))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var subtitleLine: String {
        guard let state = session.state,
              let hq = session.catalog.city(state.config.hqCity)?.name else {
            return "Regional carrier"
        }
        return "Regional carrier · \(hq) HQ"
    }

    private var reputationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Reputation")
                Spacer()
                Text("— / 100")
                    .font(.gg(13, .heavy))
                    .foregroundStyle(accent)
            }
            ThemeProgressBar(value: 0, tint: accent, height: 8)
            Text("Reputation unlocks larger tenders in a later update.")
                .font(.gg(11, .heavy))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(14)
        .surfacePanel(cornerRadius: 20)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            statTile("Active jobs", "\((session.state?.activeJobs.count ?? 0))")
            statTile("Delivered", "\((session.state?.stats.deliveredJobs ?? 0))")
            statTile("Fleet", "\((session.state?.vehicles.count ?? 0))")
            let onTime = "—"
            statTile("On-time", onTime, tint: Theme.mint)
        }
    }

    private func statTile(_ label: String, _ value: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.gg(10, .heavy))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.gg(19, .heavy))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .surfacePanel(cornerRadius: 16)
    }

    private var linkRows: some View {
        VStack(spacing: 9) {
            NavigationLink(value: CompanyDestination.finance) {
                companyLinkRow(
                    title: "Finance",
                    subtitle: financeSubtitle,
                    symbol: "chart.bar.fill",
                    tint: Theme.mint
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: CompanyDestination.facilities) {
                companyLinkRow(
                    title: "Facilities",
                    subtitle: "HQ only · warehouses coming soon",
                    symbol: "building.fill",
                    tint: Theme.sky
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: CompanyDestination.personnel) {
                companyLinkRow(
                    title: "Personnel",
                    subtitle: "Drivers and managers — coming soon",
                    symbol: "person.2.fill",
                    tint: Theme.violet
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: CompanyDestination.contracts) {
                companyLinkRow(
                    title: "Contracts",
                    subtitle: "Long-term deals — coming soon",
                    symbol: "doc.text.fill",
                    tint: accent
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var financeSubtitle: String {
        let profit = (session.state?.stats.totalRevenue ?? 0) - (session.state?.stats.totalCost ?? 0)
        let cash = session.state?.cash ?? 0
        return "Net \(Format.money(profit)) · cash \(Format.money(cash))"
    }

    private func companyLinkRow(title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.gg(13.5, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .surfacePanel(cornerRadius: 18)
    }

    private var exitButton: some View {
        Button {
            showsExitConfirm = true
        } label: {
            Text("Save & Exit to Menu")
                .font(.gg(14, .heavy))
                .foregroundStyle(Theme.coral)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .surfacePanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
        .confirmationDialog("Leave the campaign?", isPresented: $showsExitConfirm, titleVisibility: .visible) {
            Button("Save & Exit", role: .destructive) { session.quitToMenu() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private enum CompanyDestination: Hashable {
    case finance, facilities, personnel, contracts

    var title: String {
        switch self {
        case .finance: return "Finance"
        case .facilities: return "Facilities"
        case .personnel: return "Personnel"
        case .contracts: return "Contracts"
        }
    }

    var placeholder: String {
        switch self {
        case .finance: return ""
        case .facilities: return ""
        case .personnel: return "Hire drivers and managers when the personnel system ships."
        case .contracts: return "Long-term contracts and tenders will live here."
        }
    }
}

private struct ComingSoonDetail: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.gg(14, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfacePanel(cornerRadius: 18)
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.backgroundBottom.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
