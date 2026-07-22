//
//  ContractHeadline.swift
//  Goods&Glory
//
//  The top of every contract card: the two numbers a commitment is actually
//  made of. Shared by the contract market and the city screen so the same
//  offer never reads differently in two places.
//
//  It deliberately does not show a profit line. A contract creates no freight —
//  it reserves a share of a lane the world already produces — so "does this
//  lane pay for a truck" is the wrong question and, priced that way, almost
//  every honest offer looked like a loss.
//

import SwiftUI

struct ContractHeadline: View {
    let brief: SimulationEngine.ContractBrief
    var accent: Color
    /// Tonnage promised before and after signing, against what the fleet can
    /// move. One card cannot see the book it is joining, and three reasonable
    /// contracts on one lane quietly committed three trucks the player had two
    /// of — the penalties arrived a week later with no warning in between.
    var commitment: (committed: Int, after: Int, capacity: Int)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            columns
            if let commitment {
                commitmentBar(commitment)
            }
        }
    }

    @ViewBuilder private func commitmentBar(
        _ load: (committed: Int, after: Int, capacity: Int)
    ) -> some View {
        let share = Double(load.after) / Double(max(1, load.capacity))
        let oversold = load.after > load.capacity
        VStack(alignment: .leading, spacing: 4) {
            ThemeProgressBar(
                value: min(1, share),
                tint: oversold ? Theme.coral : (share > 0.8 ? Theme.warning : Theme.mint),
                height: 4
            )
            Text(oversold
                 ? String(localized: "Signing books \(Format.mass(kg: load.after))/day against a fleet that moves \(Format.mass(kg: load.capacity))/day — something will be late")
                 : String(localized: "Books \(Format.mass(kg: load.after))/day of your fleet's \(Format.mass(kg: load.capacity))/day"))
                .font(.gg(10, .bold))
                .foregroundStyle(oversold ? Theme.coral : Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var columns: some View {
        HStack(spacing: 12) {
            column(
                value: Format.mass(kg: brief.committedKgPerDay),
                unit: String(localized: "/ day locked"),
                caption: String(localized: "guaranteed share"),
                tint: accent
            )
            Rectangle()
                .fill(Theme.stroke)
                .frame(width: 1, height: 34)
            column(
                value: "+\(Format.money(brief.premiumPerDay))",
                unit: String(localized: "/ day"),
                caption: String(localized: "over the spot rate"),
                tint: Theme.mint
            )
        }
    }

    private func column(value: String, unit: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.gg(21, .heavy))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(unit)
                    .font(.gg(10.5, .heavy))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(caption)
                .font(.gg(10, .bold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
