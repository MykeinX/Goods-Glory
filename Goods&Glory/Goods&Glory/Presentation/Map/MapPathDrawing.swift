//
//  MapPathDrawing.swift
//  Goods&Glory
//
//  Shared path primitives used by the batched SpriteKit map layers.
//

import CoreGraphics

extension CGMutablePath {
    /// Straight polygon edges with a small, globally consistent corner radius.
    ///
    /// The fixed cap prevents large continental segments from becoming
    /// bulbous, while the edge fraction keeps small islands from collapsing.
    /// This reads like an iOS rounded rectangle applied to a low-poly map.
    func addRoundedClosedPolyline(
        _ points: [CGPoint],
        cornerRadius: CGFloat = 220,
        maximumCornerFraction: CGFloat = 0.28
    ) {
        guard points.count >= 3 else { return }

        func inset(
            _ vertex: CGPoint,
            toward neighbor: CGPoint,
            distance: CGFloat
        ) -> CGPoint {
            let dx = neighbor.x - vertex.x
            let dy = neighbor.y - vertex.y
            let length = hypot(dx, dy)
            guard length > 0.001 else { return vertex }
            let fraction = min(1, distance / length)
            return CGPoint(
                x: vertex.x + dx * fraction,
                y: vertex.y + dy * fraction
            )
        }

        func corner(at index: Int) -> (inlet: CGPoint, outlet: CGPoint) {
            let previous = points[(index - 1 + points.count) % points.count]
            let vertex = points[index]
            let next = points[(index + 1) % points.count]
            let incomingLength = hypot(vertex.x - previous.x, vertex.y - previous.y)
            let outgoingLength = hypot(next.x - vertex.x, next.y - vertex.y)
            let trim = min(
                cornerRadius,
                incomingLength * maximumCornerFraction,
                outgoingLength * maximumCornerFraction
            )
            return (
                inset(vertex, toward: previous, distance: trim),
                inset(vertex, toward: next, distance: trim)
            )
        }

        move(to: corner(at: 0).outlet)
        for index in 1...points.count {
            let vertexIndex = index % points.count
            let vertex = points[vertexIndex]
            let rounded = corner(at: vertexIndex)
            addLine(to: rounded.inlet)
            addQuadCurve(
                to: rounded.outlet,
                control: vertex
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
