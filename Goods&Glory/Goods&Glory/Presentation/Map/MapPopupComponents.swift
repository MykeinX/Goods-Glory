//
//  MapPopupComponents.swift
//  Goods&Glory
//
//  The shared furniture of a map popup: the chip, the chip row that wraps it,
//  the close button and the "open the full screen" call to action.
//
//  Both the city card and the vehicle card are built from these. They lived
//  inside the vehicle popup, which meant the city card reached across a file
//  for them — the shape of a component that never got its own home.
//

import SwiftUI

struct MapPopupChip: Identifiable {
    var id: String { text }
    let text: String
    let emphasized: Bool
}

func chipRow(_ chips: [MapPopupChip]) -> some View {
    FlowWrappingHStack(spacing: 6) {
        ForEach(chips) { chip in
            Text(chip.text)
                .font(.gg(11, .heavy))
                .foregroundStyle(chip.emphasized ? Theme.brand : Theme.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        chip.emphasized
                            ? Theme.brand.opacity(0.12)
                            : Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.10)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        chip.emphasized ? Theme.brand.opacity(0.3) : Theme.strokeSoft,
                        lineWidth: 1
                    )
                )
        }
    }
}

func closeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(Theme.textSecondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.12)))
    }
    .buttonStyle(.plain)
}

func detailCTA(title: String, border: Color, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(title)
            .font(.gg(12.5, .heavy))
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Theme.brand.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }
    .buttonStyle(.plain)
}

/// Simple wrapping row for popup chips (avoids a heavier layout dependency).
struct FlowWrappingHStack: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var height: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            height = max(height, y + rowHeight)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
