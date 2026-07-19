//
//  DesignSystem.swift
//  Goods&Glory
//
//  Shared visual language — "Gece Haritası": a warm, premium night-logistics
//  theme. Deep navy grounds, an amber brand accent, warm off-white text and
//  rounded, heavy typography so the game reads as one product — the player's
//  empire dashboard, not a set of stock iOS forms.
//

import SwiftUI

enum Theme {
    // MARK: Grounds
    /// Primary app background (deep navy night).
    static let backgroundTop = Color(hex6: 0x0A1220)
    /// Slightly lifted background used by list-style screens.
    static let backgroundBottom = Color(hex6: 0x0C1626)

    // MARK: Surfaces
    /// Card fill.
    static let surface = Color(hex6: 0x14243A)
    /// Glassy floating surface (used over the map).
    static let surfaceGlass = Color(red: 20/255, green: 32/255, blue: 54/255).opacity(0.92)
    /// Hairline stroke — a cool blue-grey at low opacity.
    static let stroke = Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.16)
    static let strokeSoft = Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.12)

    // MARK: Text
    static let textPrimary = Color(hex6: 0xF2EDE3)
    static let textSecondary = Color(red: 240/255, green: 235/255, blue: 225/255).opacity(0.58)
    static let textTertiary = Color(red: 240/255, green: 235/255, blue: 225/255).opacity(0.42)

    // MARK: Accents
    /// Amber brand accent (default). Individual companies may override via hex.
    static let gold = Color(hex6: 0xFFB037)
    static let brand = Color(hex6: 0xFFB037)
    /// Ink used for text/icons sitting on top of the brand color.
    static let onBrand = Color(hex6: 0x241500)
    static let mint = Color(hex6: 0x4FD6A4)
    static let sky = Color(hex6: 0x57B2FF)
    static let coral = Color(hex6: 0xFF6B5E)
    static let violet = Color(hex6: 0x9B8CFF)
    static let warning = Color(hex6: 0xFFB037)

    static var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Contrasting ink for a given accent (dark on light-ish, textPrimary otherwise).
    static func ink(on accent: Color) -> Color { onBrand }
}

extension Color {
    /// Convenience initializer from a 0xRRGGBB literal.
    init(hex6 value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

extension Font {
    /// Rounded, heavy display type approximating the mockup's Nunito.
    static func gg(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Background

/// Full-screen themed background with a faint decorative route network,
/// so even static screens feel like part of a living logistics world.
struct ThemeBackground: View {
    var showsRoutes: Bool = true

    var body: some View {
        ZStack {
            Theme.backgroundGradient
            if showsRoutes {
                RouteTexture().opacity(0.5)
            }
        }
        .ignoresSafeArea()
    }
}

/// Decorative arcs and nodes reminiscent of a route map. Purely visual.
private struct RouteTexture: View {
    var body: some View {
        Canvas { context, size in
            let nodes: [CGPoint] = [
                CGPoint(x: 0.12, y: 0.18), CGPoint(x: 0.42, y: 0.09),
                CGPoint(x: 0.85, y: 0.16), CGPoint(x: 0.70, y: 0.38),
                CGPoint(x: 0.20, y: 0.52), CGPoint(x: 0.55, y: 0.63),
                CGPoint(x: 0.90, y: 0.58), CGPoint(x: 0.33, y: 0.84),
                CGPoint(x: 0.75, y: 0.90)
            ].map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }

            let links: [(Int, Int)] = [(0, 1), (1, 2), (1, 3), (3, 5), (4, 5), (5, 6), (4, 7), (5, 8), (2, 6)]
            for (a, b) in links {
                var path = Path()
                let start = nodes[a]
                let end = nodes[b]
                let mid = CGPoint(
                    x: (start.x + end.x) / 2 + (start.y - end.y) * 0.18,
                    y: (start.y + end.y) / 2 + (end.x - start.x) * 0.18
                )
                path.move(to: start)
                path.addQuadCurve(to: end, control: mid)
                context.stroke(
                    path,
                    with: .color(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.06)),
                    style: StrokeStyle(lineWidth: 1.2, dash: [1, 6])
                )
            }
            for node in nodes {
                let rect = CGRect(x: node.x - 2, y: node.y - 2, width: 4, height: 4)
                context.fill(Path(ellipseIn: rect), with: .color(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.10)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Cards

extension View {
    /// A plain rounded surface panel (no inner padding management).
    func surfacePanel(cornerRadius: CGFloat = 20, selected: Bool = false, accent: Color = Theme.brand) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(selected ? accent : Theme.stroke, lineWidth: selected ? 1.6 : 1)
            )
    }
}

// MARK: - Buttons

/// Filled brand call-to-action: rounded rectangle, warm shadow, dark ink.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.brand

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gg(16, .heavy))
            .foregroundStyle(Theme.ink(on: tint))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(tint)
            )
            .shadow(color: tint.opacity(0.30), radius: 14, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Quiet surface button.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gg(15, .bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.stroke, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Small components

/// Compact icon + value chip used on cards.
struct StatChip: View {
    let symbol: String
    let text: String
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.gg(12, .bold))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.10))
        )
    }
}

/// A tiny uppercase pill tag (e.g. "URGENT", "CONTRACT").
struct TagPill: View {
    let text: String
    var color: Color = Theme.brand
    var body: some View {
        Text(text.uppercased())
            .font(.gg(10, .heavy))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}

/// Uppercase micro section label.
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.gg(11, .heavy))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
    }
}

/// A slim progress bar with a tinted fill.
struct ThemeProgressBar: View {
    var value: Double            // 0...1
    var tint: Color = Theme.brand
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 140/255, green: 170/255, blue: 215/255).opacity(0.14))
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Labeled metric row used on city founding / detail cards.
struct MetricBar: View {
    let label: String
    let progress: Double
    var tint: Color = Theme.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.gg(10.5, .heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
            ThemeProgressBar(value: progress, tint: tint, height: 7)
        }
    }
}

/// Population shown in the design’s tag slot (icon + compact count).
struct PopulationPill: View {
    let population: Int
    var color: Color = Theme.brand

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 9, weight: .heavy))
            Text(population.formatted(.number.notation(.compactName)))
                .font(.gg(10.5, .heavy))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.14)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Population"))
        .accessibilityValue(Text(population.formatted()))
    }
}

/// The company mark: emblem in a rounded, glowing tile of the brand color.
struct CompanyMark: View {
    let emblemSymbol: String
    let color: Color
    var size: CGFloat = 56

    var body: some View {
        Image(systemName: emblemSymbol)
            .font(.system(size: size * 0.44, weight: .bold))
            .foregroundStyle(Theme.onBrand)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous).fill(color)
            )
            .shadow(color: color.opacity(0.40), radius: size * 0.2, y: 3)
    }
}

/// Step dots for the founding flow.
struct StepIndicator: View {
    let current: Int
    let total: Int
    var accent: Color = Theme.brand

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? accent : Color.white.opacity(0.15))
                    .frame(width: index == current ? 24 : 10, height: 5)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: current)
    }
}
