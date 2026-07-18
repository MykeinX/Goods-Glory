//
//  AnimatedWorldBackground.swift
//  Goods&Glory
//
//  Living logistics backdrop for the title screen: a stylized route network
//  with freight glyphs travelling along the corridors and pulsing city nodes.
//  Purely decorative — no game state involved.
//

import SwiftUI

struct AnimatedWorldBackground: View {
    var body: some View {
        ZStack {
            Theme.backgroundGradient
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    Self.draw(in: &context, size: size, time: time)
                }
            }
            // Keep the center readable for the logo and buttons.
            RadialGradient(
                colors: [Theme.backgroundTop.opacity(0.55), .clear],
                center: .center,
                startRadius: 40,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Static network layout (relative coordinates)

    private struct Corridor {
        let from: Int
        let to: Int
        /// Perpendicular bow of the arc; sign flips the curve side.
        let bow: CGFloat
        let glyph: String
        let tint: Color
        let speed: Double
        let phase: Double
    }

    private static let nodes: [CGPoint] = [
        CGPoint(x: 0.10, y: 0.14), CGPoint(x: 0.46, y: 0.07),
        CGPoint(x: 0.88, y: 0.13), CGPoint(x: 0.74, y: 0.33),
        CGPoint(x: 0.16, y: 0.42), CGPoint(x: 0.50, y: 0.52),
        CGPoint(x: 0.90, y: 0.55), CGPoint(x: 0.28, y: 0.78),
        CGPoint(x: 0.68, y: 0.88), CGPoint(x: 0.08, y: 0.94)
    ]

    private static let corridors: [Corridor] = [
        Corridor(from: 0, to: 1, bow: 0.14, glyph: "airplane", tint: Color(red: 0.45, green: 0.75, blue: 0.95), speed: 0.10, phase: 0.00),
        Corridor(from: 1, to: 2, bow: -0.12, glyph: "box.truck.fill", tint: Theme.gold, speed: 0.055, phase: 0.35),
        Corridor(from: 1, to: 3, bow: 0.10, glyph: "box.truck.fill", tint: Theme.gold, speed: 0.065, phase: 0.60),
        Corridor(from: 3, to: 5, bow: 0.12, glyph: "ferry.fill", tint: Color(red: 0.45, green: 0.85, blue: 0.75), speed: 0.04, phase: 0.15),
        Corridor(from: 4, to: 5, bow: -0.10, glyph: "box.truck.fill", tint: Theme.gold, speed: 0.06, phase: 0.80),
        Corridor(from: 5, to: 6, bow: 0.10, glyph: "airplane", tint: Color(red: 0.45, green: 0.75, blue: 0.95), speed: 0.12, phase: 0.45),
        Corridor(from: 4, to: 7, bow: 0.12, glyph: "box.truck.fill", tint: Theme.gold, speed: 0.05, phase: 0.25),
        Corridor(from: 5, to: 8, bow: -0.12, glyph: "box.truck.fill", tint: Theme.gold, speed: 0.07, phase: 0.55),
        Corridor(from: 7, to: 9, bow: -0.10, glyph: "ferry.fill", tint: Color(red: 0.45, green: 0.85, blue: 0.75), speed: 0.045, phase: 0.70),
        Corridor(from: 2, to: 6, bow: 0.13, glyph: "airplane", tint: Color(red: 0.45, green: 0.75, blue: 0.95), speed: 0.11, phase: 0.90),
        Corridor(from: 7, to: 8, bow: 0.09, glyph: "box.truck.fill", tint: Theme.gold, speed: 0.06, phase: 0.10)
    ]

    // MARK: - Drawing

    private static func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let points = nodes.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }

        // Corridor arcs
        for corridor in corridors {
            let path = arcPath(corridor, points: points)
            context.stroke(
                path,
                with: .color(.white.opacity(0.07)),
                style: StrokeStyle(lineWidth: 1.4, dash: [2, 7])
            )
        }

        // Moving freight glyphs with a fading trail
        for corridor in corridors {
            let progress = (time * corridor.speed + corridor.phase).truncatingRemainder(dividingBy: 1)
            let start = points[corridor.from]
            let end = points[corridor.to]
            let control = controlPoint(corridor, start: start, end: end)

            // Trail dots behind the glyph
            for trailStep in 1...3 {
                let trailT = progress - Double(trailStep) * 0.03
                guard trailT > 0 else { continue }
                let position = bezierPoint(CGFloat(trailT), start, control, end)
                let radius = 2.4 - CGFloat(trailStep) * 0.6
                context.fill(
                    Path(ellipseIn: CGRect(x: position.x - radius, y: position.y - radius,
                                           width: radius * 2, height: radius * 2)),
                    with: .color(corridor.tint.opacity(0.35 - Double(trailStep) * 0.09))
                )
            }

            let position = bezierPoint(CGFloat(progress), start, control, end)
            let tangent = bezierTangent(CGFloat(progress), start, control, end)
            let angle = atan2(tangent.dy, tangent.dx)

            var glyphContext = context
            glyphContext.translateBy(x: position.x, y: position.y)
            glyphContext.rotate(by: .radians(angle + (corridor.glyph == "airplane" ? .pi / 2 : 0)))
            var resolved = glyphContext.resolve(
                Image(systemName: corridor.glyph)
                    .renderingMode(.template)
            )
            resolved.shading = .color(corridor.tint.opacity(0.75))
            glyphContext.draw(
                resolved,
                in: CGRect(x: -7, y: -7, width: 14, height: 14)
            )
        }

        // Pulsing city nodes
        for (index, point) in points.enumerated() {
            let pulse = 0.5 + 0.5 * sin(time * 1.6 + Double(index) * 1.1)
            let radius = 2.5 + CGFloat(pulse) * 1.5
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(.white.opacity(0.14 + pulse * 0.12))
            )
            let glowRadius = radius + 5
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - glowRadius, y: point.y - glowRadius,
                                       width: glowRadius * 2, height: glowRadius * 2)),
                with: .color(Theme.gold.opacity(0.03 + pulse * 0.04))
            )
        }
    }

    private static func controlPoint(_ corridor: Corridor, start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: (start.x + end.x) / 2 + (start.y - end.y) * corridor.bow,
            y: (start.y + end.y) / 2 + (end.x - start.x) * corridor.bow
        )
    }

    private static func arcPath(_ corridor: Corridor, points: [CGPoint]) -> Path {
        var path = Path()
        let start = points[corridor.from]
        let end = points[corridor.to]
        path.move(to: start)
        path.addQuadCurve(to: end, control: controlPoint(corridor, start: start, end: end))
        return path
    }

    /// Quadratic bezier: (1-t)²·p0 + 2(1-t)t·c + t²·p1
    private static func bezierPoint(_ t: CGFloat, _ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * p0.x + 2 * inverse * t * c.x + t * t * p1.x,
            y: inverse * inverse * p0.y + 2 * inverse * t * c.y + t * t * p1.y
        )
    }

    /// Derivative of the quadratic bezier, for glyph heading.
    private static func bezierTangent(_ t: CGFloat, _ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) -> CGVector {
        let inverse = 1 - t
        return CGVector(
            dx: 2 * inverse * (c.x - p0.x) + 2 * t * (p1.x - c.x),
            dy: 2 * inverse * (c.y - p0.y) + 2 * t * (p1.y - c.y)
        )
    }
}
