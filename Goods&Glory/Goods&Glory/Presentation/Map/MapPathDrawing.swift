//
//  MapPathDrawing.swift
//  Goods&Glory
//
//  Shared path primitives used by the batched SpriteKit map layers.
//

import CoreGraphics

extension CGMutablePath {
    /// Draws fixed-radius iOS-style corners as native quadratic curves.
    /// The sampled variant in `MapPathSimplifier` remains for geometry that
    /// vehicles must physically follow; static land can keep the smaller path.
    func addRoundedClosedPolyline(
        _ points: [CGPoint],
        cornerRadius: CGFloat,
        maximumCornerFraction: CGFloat
    ) {
        guard points.count >= 3 else { return }
        let corners = points.indices.compactMap {
            MapPathSimplifier.roundedCorner(
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
