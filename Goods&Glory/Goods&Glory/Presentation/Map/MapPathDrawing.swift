//
//  MapPathDrawing.swift
//  Goods&Glory
//
//  Shared path primitives used by the batched SpriteKit map layers.
//

import CoreGraphics
import Foundation

extension CGMutablePath {
    /// Draws fixed-radius iOS-style corners as native quadratic curves.
    ///
    /// The board silhouette arrives octilinear from `build_board.py`, so every
    /// corner here is a 45° or 90° turn and rounding is the whole of the
    /// styling done at render time.
    func addRoundedClosedPolyline(
        _ points: [CGPoint],
        cornerRadius: CGFloat,
        maximumCornerFraction: CGFloat
    ) {
        guard points.count >= 3 else { return }
        let corners = points.indices.compactMap {
            MapCorner.rounded(
                at: $0,
                in: points,
                radius: cornerRadius,
                cornerFraction: maximumCornerFraction
            )
        }
        guard corners.count == points.count else {
            addClosedPolyline(points)
            return
        }

        move(to: corners[0].outlet)
        for index in 1...points.count {
            let vertexIndex = index % points.count
            addLine(to: corners[vertexIndex].inlet)
            addQuadCurve(
                to: corners[vertexIndex].outlet,
                control: points[vertexIndex]
            )
        }
        closeSubpath()
    }

    func addClosedPolyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
        closeSubpath()
    }

    func addOpenPolyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }
}

enum MapCorner {
    /// Where a rounded corner leaves the incoming edge and rejoins the outgoing
    /// one.
    ///
    /// The radius is fixed rather than proportional: a corner between two
    /// continent-sized coast edges gets the same "iOS box radius" as a small
    /// one, which is the flat-icon look of the game board. `cornerFraction`
    /// caps it as a share of each adjacent edge so tight bends never overlap
    /// their own rounding.
    static func rounded(
        at index: Int,
        in points: [CGPoint],
        radius: CGFloat,
        cornerFraction: CGFloat
    ) -> (inlet: CGPoint, outlet: CGPoint)? {
        let previous = points[(index - 1 + points.count) % points.count]
        let corner = points[index]
        let next = points[(index + 1) % points.count]
        let incomingLength = hypot(corner.x - previous.x, corner.y - previous.y)
        let outgoingLength = hypot(next.x - corner.x, next.y - corner.y)
        guard incomingLength > 0.01, outgoingLength > 0.01 else { return nil }

        let offset = min(
            radius,
            incomingLength * cornerFraction,
            outgoingLength * cornerFraction
        )
        return (
            CGPoint(
                x: corner.x + (previous.x - corner.x) * offset / incomingLength,
                y: corner.y + (previous.y - corner.y) * offset / incomingLength
            ),
            CGPoint(
                x: corner.x + (next.x - corner.x) * offset / outgoingLength,
                y: corner.y + (next.y - corner.y) * offset / outgoingLength
            )
        )
    }
}
