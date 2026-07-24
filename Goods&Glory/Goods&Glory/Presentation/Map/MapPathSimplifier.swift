//
//  MapPathSimplifier.swift
//  Goods&Glory
//
//  Display-budget polyline simplification for the strategic map. Simulation
//  uses the road graph (nodes + distanceKm); only projected geography drawing
//  is thinned so SpriteKit stays light.
//

import CoreGraphics
import Foundation

enum MapPathSimplifier {
    /// World units ≈ km under MapProjection. Aggressive enough for a game map
    /// while keeping interstate corridor shape and endpoint alignment.
    static let displayToleranceKm: CGFloat = 4

    /// Douglas–Peucker. Endpoints are always kept.
    static func simplify(
        _ points: [CGPoint],
        tolerance: CGFloat = displayToleranceKm
    ) -> [CGPoint] {
        guard points.count > 2, tolerance > 0 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        simplifySection(
            points,
            start: 0,
            end: points.count - 1,
            toleranceSquared: tolerance * tolerance,
            keep: &keep
        )
        return zip(points, keep).compactMap { point, keepFlag in keepFlag ? point : nil }
    }

    /// Fixed-radius corner rounding: every corner is replaced by a quadratic
    /// bezier sampled into the polyline itself, so consumers that walk the
    /// geometry (vehicles on corridors) follow exactly the drawn soft bend.
    ///
    /// Unlike Chaikin, the radius does not grow with edge length — a corner
    /// between two continent-sized coast edges gets the same "iOS box radius"
    /// as a small one, which is the flat-icon look of the game board.
    ///
    /// - Parameters:
    ///   - radius: rounding radius in world units (≈ km).
    ///   - cornerFraction: cap as a share of each adjacent edge, so tight
    ///     zigzags never overlap their own rounding.
    ///   - closed: treat the points as a ring (no pinned endpoints).
    static func roundedPolyline(
        _ points: [CGPoint],
        radius: CGFloat,
        cornerFraction: CGFloat = 0.22,
        samplesPerCorner: Int = 5,
        closed: Bool = false
    ) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        var result: [CGPoint] = []
        result.reserveCapacity(points.count * (samplesPerCorner + 1))
        if !closed { result.append(points[0]) }

        let cornerRange = closed ? 0..<points.count : 1..<(points.count - 1)
        for index in cornerRange {
            guard let rounded = roundedCorner(
                at: index,
                in: points,
                radius: radius,
                cornerFraction: cornerFraction
            ) else { continue }
            let corner = points[index]
            let inlet = rounded.inlet
            let outlet = rounded.outlet
            result.append(inlet)

            for sample in 1...samplesPerCorner {
                let t = CGFloat(sample) / CGFloat(samplesPerCorner)
                let inverse = 1 - t
                result.append(CGPoint(
                    x: inverse * inverse * inlet.x
                        + 2 * inverse * t * corner.x
                        + t * t * outlet.x,
                    y: inverse * inverse * inlet.y
                        + 2 * inverse * t * corner.y
                        + t * t * outlet.y
                ))
            }
        }

        if !closed { result.append(points[points.count - 1]) }
        return result
    }

    static func roundedCorner(
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

    private static func simplifySection(
        _ points: [CGPoint],
        start: Int,
        end: Int,
        toleranceSquared: CGFloat,
        keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }

        var maxDistanceSquared: CGFloat = 0
        var farthest = start
        let startPoint = points[start]
        let endPoint = points[end]
        for index in (start + 1)..<end {
            let distanceSquared = perpendicularDistanceSquared(
                points[index],
                start: startPoint,
                end: endPoint
            )
            if distanceSquared > maxDistanceSquared {
                maxDistanceSquared = distanceSquared
                farthest = index
            }
        }

        guard maxDistanceSquared > toleranceSquared else { return }
        keep[farthest] = true
        simplifySection(
            points,
            start: start,
            end: farthest,
            toleranceSquared: toleranceSquared,
            keep: &keep
        )
        simplifySection(
            points,
            start: farthest,
            end: end,
            toleranceSquared: toleranceSquared,
            keep: &keep
        )
    }

    private static func perpendicularDistanceSquared(
        _ point: CGPoint,
        start: CGPoint,
        end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0, dy == 0 {
            let ex = point.x - start.x
            let ey = point.y - start.y
            return ex * ex + ey * ey
        }
        let numerator = dx * (start.y - point.y) - dy * (start.x - point.x)
        return (numerator * numerator) / (dx * dx + dy * dy)
    }

}
