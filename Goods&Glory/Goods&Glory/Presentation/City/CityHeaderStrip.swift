//
//  CityHeaderStrip.swift
//  Goods&Glory
//
//  The pinned answer to "what kind of city is this": demand, competition and
//  which transport modes reach it. Deliberately almost wordless — the previous
//  version said the same things in sentences, and sentences do not get read.
//

import SwiftUI

struct CityHeaderStrip: View {
    @Environment(GameSession.self) private var session
    let cityID: CityID

    private var accent: Color { session.accentColor }
    private var city: CityDefinition? { session.catalog.city(cityID) }
    private var isHQ: Bool { session.state?.config.hqCity == cityID }

    private var insight: CityInsight? {
        city.map { CityInsight.make(city: $0, catalog: session.catalog) }
    }

    private var idleVehicleCount: Int {
        guard let state = session.state else { return 0 }
        let busy = state.busyVehicleIDs()
        return state.vehicles.count { $0.cityID == cityID && !busy.contains($0.id) }
    }

    private var distanceFromHQKm: Int? {
        guard let hqID = session.state?.config.hqCity, hqID != cityID,
              let route = session.catalog.shortestRoute(from: hqID, to: cityID) else { return nil }
        return Int(route.distanceKm.rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(city?.name ?? cityID.rawValue)
                    .font(.gg(21, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if isHQ {
                    TagPill(text: String(localized: "HQ"), color: Theme.sky)
                }
                Spacer(minLength: 8)
                if let insight {
                    CityAccessIcons(access: insight.access, accent: accent)
                }
            }

            HStack(spacing: 7) {
                if let city {
                    PopulationPill(population: city.population, color: Theme.textSecondary)
                }
                if let distanceFromHQKm {
                    StatChip(
                        symbol: "point.topleft.down.to.point.bottomright.curvepath",
                        text: Format.distance(km: Double(distanceFromHQKm)),
                        tint: Theme.textSecondary
                    )
                }
                StatChip(
                    symbol: "truck.box.fill",
                    text: "\(idleVehicleCount)",
                    tint: idleVehicleCount > 0 ? accent : Theme.textTertiary
                )
                Spacer(minLength: 0)
            }

            if let insight {
                HStack(spacing: 14) {
                    MetricBar(
                        label: String(localized: "Demand"),
                        progress: insight.marketSizePercent,
                        tint: Theme.mint
                    )
                    MetricBar(
                        label: String(localized: "Competition"),
                        progress: insight.competitionPercent,
                        tint: Theme.coral
                    )
                }
            }
        }
    }
}

/// The transport modes reaching a city, as a row of icons. A dim icon is
/// information too — it says the mode is missing here.
struct CityAccessIcons: View {
    let access: Set<CityAccess>
    var accent: Color = Theme.brand

    var body: some View {
        HStack(spacing: 5) {
            ForEach(CityAccess.allCases, id: \.self) { mode in
                let served = access.contains(mode)
                Image(systemName: CityAccessDisplay.symbol(mode))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(served ? accent : Theme.textTertiary.opacity(0.45))
                    .frame(width: 27, height: 27)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(served ? accent.opacity(0.14) : Theme.surface.opacity(0.6))
                    )
                    .accessibilityLabel(Text(mode.label))
                    .accessibilityValue(Text(served
                                             ? String(localized: "Available")
                                             : String(localized: "Not available")))
            }
        }
    }
}

enum CityAccessDisplay {
    static func symbol(_ mode: CityAccess) -> String {
        switch mode {
        case .road: "road.lanes"
        case .rail: "train.side.front.car"
        case .sea: "ferry.fill"
        case .air: "airplane"
        }
    }
}
