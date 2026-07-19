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

    /// Closed rings (land silhouettes). Does not duplicate the closing vertex.
    static func simplifyClosed(
        _ points: [CGPoint],
        tolerance: CGFloat = displayToleranceKm
    ) -> [CGPoint] {
        guard points.count > 3 else { return points }
        var ring = points
        if let first = ring.first, let last = ring.last,
           hypot(first.x - last.x, first.y - last.y) < 0.01 {
            ring.removeLast()
        }
        guard ring.count > 3 else { return points }
        // Anchor on the vertex farthest from the centroid so the silhouette
        // does not collapse toward an arbitrary catalog start index.
        let anchor = farthestIndex(in: ring)
        let rotated = Array(ring[anchor...]) + Array(ring[..<anchor])
        let open = rotated + [rotated[0]]
        let simplifiedOpen = simplify(open, tolerance: tolerance)
        guard simplifiedOpen.count > 1 else { return points }
        return Array(simplifiedOpen.dropLast())
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

    private static func farthestIndex(in points: [CGPoint]) -> Int {
        let centroid = CGPoint(
            x: points.reduce(0) { $0 + $1.x } / CGFloat(points.count),
            y: points.reduce(0) { $0 + $1.y } / CGFloat(points.count)
        )
        var best = 0
        var bestDistance: CGFloat = -1
        for (index, point) in points.enumerated() {
            let distance = hypot(point.x - centroid.x, point.y - centroid.y)
            if distance > bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}
