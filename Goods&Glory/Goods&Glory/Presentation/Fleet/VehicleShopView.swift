//
//  VehicleShopView.swift
//  Goods&Glory
//
//  Buying rolling stock. The choice between two trucks is an efficiency
//  choice, so the shop has to show efficiency: the old list gave a name, a
//  capacity and a price, which is exactly the information that cannot answer
//  "which of these should I buy next".
//
//  Every class is drawn against the best in the catalog, so the trade-off is
//  visible without arithmetic: bigger is cheaper per tonne and dearer per day.
//

import SwiftUI

struct VehicleShopInline: View {
    @Environment(GameSession.self) private var session
    var accent: Color
    @Binding var purchaseError: CommandError?

    private var cash: Money { session.state?.cash ?? 0 }

    /// Catalog maxima, so each bar reads as "share of the best available".
    private var peak: (mass: Int, speed: Double, economy: Double) {
        let types = session.catalog.vehicleTypes
        return (
            types.map(\.capacity.massKg).max() ?? 1,
            types.map(\.speedKmh).max() ?? 1,
            // Economy is inverted: the cheapest tonne-km is the best one.
            types.map(\.costPerTonneKm).min() ?? 1
        )
    }

    private func ownedCount(_ type: VehicleTypeDefinition) -> Int {
        session.state?.vehicles.count { $0.typeID == type.id } ?? 0
    }

    var body: some View {
        let peak = peak
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(String(localized: "Rolling stock"))
                Spacer()
                Text(Format.money(cash))
                    .font(.gg(13, .heavy))
                    .foregroundStyle(Theme.mint)
                    .monospacedDigit()
            }

            ForEach(session.catalog.vehicleTypes) { type in
                VehicleShopCard(
                    type: type,
                    ownedCount: ownedCount(type),
                    cash: cash,
                    peak: peak,
                    accent: accent,
                    onBuy: {
                        if let error = session.perform(.buyVehicle(type.id)) {
                            purchaseError = error
                        }
                    }
                )
            }

            SectionLabel(String(localized: "Add-ons"))
            Text("Trailers and reefers unlock in a later update.")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surfacePanel(cornerRadius: 18)
        }
    }
}

struct VehicleShopCard: View {
    let type: VehicleTypeDefinition
    let ownedCount: Int
    let cash: Money
    let peak: (mass: Int, speed: Double, economy: Double)
    var accent: Color
    var onBuy: () -> Void

    private var affordable: Bool { cash >= type.purchasePrice }
    private var shortfall: Money { max(0, type.purchasePrice - cash) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
            bars
            runningCosts
            buyButton
        }
        .padding(14)
        .surfacePanel(cornerRadius: 20)
        .opacity(affordable ? 1 : 0.72)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 48, height: 48)
                Image(systemName: type.symbol)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(String(localized: String.LocalizationValue(type.name)))
                        .font(.gg(16, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if ownedCount > 0 {
                        TagPill(text: String(localized: "\(ownedCount) owned"), color: Theme.sky)
                    }
                }
                HStack(spacing: 7) {
                    StatChip(
                        symbol: "scalemass.fill",
                        text: Format.mass(kg: type.capacity.massKg),
                        tint: Theme.textSecondary
                    )
                    StatChip(
                        symbol: "cube.fill",
                        text: Format.volume(m3: type.capacity.volumeM3),
                        tint: Theme.textSecondary
                    )
                    StatChip(
                        symbol: "speedometer",
                        text: "\(Int(type.speedKmh))",
                        tint: Theme.textSecondary
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Three bars against the best class in the catalog. Payload and speed read
    /// directly; economy is inverted so a longer bar is always better.
    private var bars: some View {
        VStack(spacing: 6) {
            bar(
                label: String(localized: "Payload"),
                value: Double(type.capacity.massKg) / Double(max(1, peak.mass)),
                tint: Theme.mint
            )
            bar(
                label: String(localized: "Speed"),
                value: type.speedKmh / max(1, peak.speed),
                tint: Theme.sky
            )
            bar(
                label: String(localized: "Economy"),
                value: peak.economy / max(0.0001, type.costPerTonneKm),
                tint: accent
            )
        }
    }

    private func bar(label: String, value: Double, tint: Color) -> some View {
        HStack(spacing: 9) {
            Text(label.uppercased())
                .font(.gg(9.5, .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 62, alignment: .leading)
            ThemeProgressBar(value: min(1, max(0, value)), tint: tint, height: 5)
        }
    }

    /// What it costs once it is on the road — the half of the price the sticker
    /// never shows.
    private var runningCosts: some View {
        HStack(spacing: 7) {
            StatChip(
                symbol: "fuelpump.fill",
                text: String(format: "$%.2f/km", type.operatingCostPerKm),
                tint: Theme.textSecondary
            )
            StatChip(
                symbol: "shippingbox.fill",
                text: String(format: "$%.2f/t·km", type.costPerTonneKm),
                tint: Theme.mint
            )
            StatChip(
                symbol: "calendar",
                text: "\(Format.money(Money(type.fixedCostPerDay.rounded())))/d",
                tint: Theme.warning
            )
            Spacer(minLength: 0)
        }
    }

    private var buyButton: some View {
        Button(action: onBuy) {
            HStack(spacing: 6) {
                Image(systemName: affordable ? "plus.circle.fill" : "lock.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(affordable
                     ? Format.money(type.purchasePrice)
                     : String(localized: "\(Format.money(shortfall)) short"))
                    .font(.gg(13.5, .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(affordable ? Theme.onBrand : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(affordable ? accent : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(affordable ? .clear : Theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!affordable)
    }
}
