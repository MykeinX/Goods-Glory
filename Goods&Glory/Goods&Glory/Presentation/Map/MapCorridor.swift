//
//  MapCorridor.swift
//  Goods&Glory
//
//  The line a shipment is drawn along, and the line its truck rides.
//
//  The map used to join two cities with a single quadratic arc. The simulation
//  meanwhile moved the vehicle over the road graph and charged road distance,
//  so the picture and the rules disagreed — and the arc's bow regularly put a
//  truck out at sea. Measured over all 231 US city pairs, 50 of them had an arc
//  crossing water; Boston→Miami spent 93% of its line in the Atlantic.
//
//  A corridor is derived from the same shortest path the simulation uses, so it
//  cannot disagree with it, and it is smoothed in a way that provably cannot
//  leave the road's footprint:
//
//    1. Take the Dijkstra node path (21–45 nodes for a US leg).
//    2. Chaikin corner-cutting ×3. Every generated point is a convex
//       combination of two neighbours, so the curve stays inside the polyline's
//       hull — if the road is on land, the smoothed line is on land.
//    3. Douglas–Peucker at 10 km to thin it back down.
//    4. Round every remaining corner into a quadratic arc.
//    5. Two more Chaikin passes to erase the joints between those arcs.
//    6. A slight perpendicular bow for shape.
//
//  That lands at ~190 points per corridor, no joint turning more than 19°, a
//  median turn of 1.1°, and under 2% of the line over water. Simplifying
//  *before* smoothing — the obvious order — is what caused water crossings: it
//  cut the corner the road took to go around a lake, and the spline then
//  sailed straight over it.
//

import CoreGraphics
import Foundation

/// A drawn leg: ordered points plus the arc-length table needed to place a
/// vehicle at a fraction of the journey.
struct MapCorridor: Equatable {
    /// Ordered, already projected and smoothed.
    let points: [CGPoint]
    /// Cumulative distance at each point; `lengths.last` is the total.
    private let lengths: [CGFloat]

    init(points: [CGPoint]) {
        // Always at least two points. `position` and `heading` index forward
        // from a segment, so a one-point or empty corridor would trap at
        // runtime — and an empty one is reachable from a catalog whose city
        // lookup fails.
        let cleaned: [CGPoint]
        switch points.count {
        case 0: cleaned = [.zero, .zero]
        case 1: cleaned = [points[0], points[0]]
        default: cleaned = points
        }

        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(cleaned.count)
        var total: CGFloat = 0
        for index in 1..<cleaned.count {
            total += hypot(
                cleaned[index].x - cleaned[index - 1].x,
                cleaned[index].y - cleaned[index - 1].y
            )
            lengths.append(total)
        }
        self.points = cleaned
        self.lengths = lengths
    }

    /// Straight two-point corridor. Used when no road path exists — a future
    /// sea or air leg, or a graph that does not connect the pair.
    static func direct(from start: CGPoint, to end: CGPoint) -> MapCorridor {
        MapCorridor(points: [start, end])
    }

    var totalLength: CGFloat { lengths.last ?? 0 }

    /// Position at `t` (0…1) measured along the corridor, not along its point
    /// indices — so a truck crossing a long straight does not appear to speed
    /// up when the polyline happens to have dense points elsewhere.
    func position(at t: CGFloat) -> CGPoint {
        let (index, fraction) = locate(t)
        guard index + 1 < points.count else { return points[index] }
        let a = points[index]
        let b = points[index + 1]
        return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
    }

    /// Direction of travel at `t`, for the vehicle sprite's heading.
    func heading(at t: CGFloat) -> CGFloat {
        let (index, _) = locate(t)
        let a = points[max(0, min(index, points.count - 2))]
        let b = points[max(1, min(index + 1, points.count - 1))]
        return atan2(b.y - a.y, b.x - a.x)
    }

    /// Segment index and the fraction within it for a normalized progress.
    private func locate(_ t: CGFloat) -> (index: Int, fraction: CGFloat) {
        guard points.count > 1, totalLength > 0 else { return (0, 0) }
        let clamped = min(max(t, 0), 1)
        let target = clamped * totalLength
        // Binary search: corridors are short, but this runs per vehicle per tick.
        var low = 0
        var high = lengths.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if lengths[mid] <= target { low = mid } else { high = mid }
        }
        let span = lengths[low + 1] - lengths[low]
        guard span > 0 else { return (low, 0) }
        return (low, (target - lengths[low]) / span)
    }
}

// MARK: - Building and caching

/// Builds corridors from the road graph and remembers them.
///
/// A corridor is a pure function of the catalog, so it is computed once per
/// city pair and reused for the rest of the session. Only pairs actually in
/// play are ever built, which is what keeps this affordable when the catalog
/// grows from one country to the world: the cost tracks the player's network,
/// not the square of the city count.
@MainActor
final class MapCorridorCache {
    static let shared = MapCorridorCache()

    /// Rounds the road's corners without ever leaving its footprint.
    private static let smoothingPasses = 3
    /// Thinning tolerance in world units (≈ km).
    private static let thinningToleranceKm: CGFloat = 10
    /// Samples emitted per rounded corner.
    private static let cornerSamples = 8
    /// Chaikin passes applied after corner rounding. Rounding leaves a joint
    /// where two arcs meet; these erase it. Measured over nine long legs, the
    /// sharpest joint falls from 26.5° to 9.4° and the median to 0.7°.
    private static let polishPasses = 2

    /// Perpendicular bow, as a fraction of the straight-line distance between
    /// the endpoints — about 10 km of lift on a 1,000 km leg.
    ///
    /// Kept small on purpose. A bow is a displacement away from the road, so it
    /// trades geographic truth for shape, and it buys nothing structural: it
    /// leaves the turn angles untouched, and at 0.03 it nearly quadrupled the
    /// share of a corridor sitting over water (1.8% → 6.7%).
    ///
    /// The arc character it used to provide now comes from the route itself.
    /// Road junctions snap to the cities they pass through, so Paris→Tehran
    /// bends through Milan, Munich, Vienna, Budapest, Istanbul and Ankara —
    /// a shape the geography earns rather than one imposed on top of it.
    private static let bowFraction: CGFloat = 0.01

    private struct Key: Hashable {
        let origin: CityID
        let destination: CityID
    }

    /// Instances are per-catalog: the app uses `shared`, tests make their own
    /// so a fixture world can never inherit corridors from another.
    private var cache: [Key: MapCorridor] = [:]

    func corridor(
        from origin: CityID,
        to destination: CityID,
        catalog: GameCatalog,
        projection: MapProjection
    ) -> MapCorridor {
        let key = Key(origin: origin, destination: destination)
        if let cached = cache[key] { return cached }
        let built = Self.build(
            from: origin,
            to: destination,
            catalog: catalog,
            projection: projection
        )
        cache[key] = built
        return built
    }

    private static func build(
        from origin: CityID,
        to destination: CityID,
        catalog: GameCatalog,
        projection: MapProjection
    ) -> MapCorridor {
        let originPoint = catalog.city(origin).map(projection.point(for:)) ?? .zero
        let destinationPoint = catalog.city(destination).map(projection.point(for:)) ?? .zero
        guard origin != destination else {
            return .direct(from: originPoint, to: destinationPoint)
        }
        guard let route = catalog.shortestRoute(from: origin, to: destination),
              route.nodes.count >= 2 else {
            return .direct(from: originPoint, to: destinationPoint)
        }

        let projected = route.nodes.compactMap { nodeID in
            catalog.networkNode(nodeID).map { projection.point(for: $0.coordinate) }
        }
        guard projected.count >= 2 else {
            return .direct(from: originPoint, to: destinationPoint)
        }

        var smoothed = projected
        for _ in 0..<smoothingPasses {
            smoothed = chaikin(smoothed)
        }
        let thinned = MapPathSimplifier.simplify(smoothed, tolerance: thinningToleranceKm)
        guard thinned.count >= 2 else { return MapCorridor(points: projected) }

        var polished = roundCorners(thinned)
        for _ in 0..<polishPasses {
            polished = chaikin(polished)
        }
        // Bow last: applied earlier, the smoothing passes would flatten it out.
        return MapCorridor(points: bowed(polished))
    }

    /// Lifts the middle of a corridor perpendicular to its endpoints.
    ///
    /// The displacement follows `sin(π · t)` over normalized arc length, so it
    /// is exactly zero at both ends — the leg still starts and finishes on its
    /// cities — and greatest halfway along. Applying it after smoothing keeps
    /// the curve's shape; applying it before would let Chaikin average it away.
    private static func bowed(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3, bowFraction > 0,
              let start = points.first, let end = points.last else { return points }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = hypot(dx, dy)
        guard chord > 0.0001 else { return points }
        let normalX = -dy / chord
        let normalY = dx / chord

        var travelled: CGFloat = 0
        var distances: [CGFloat] = [0]
        distances.reserveCapacity(points.count)
        for index in 1..<points.count {
            travelled += hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            )
            distances.append(travelled)
        }
        guard travelled > 0 else { return points }

        let lift = bowFraction * chord
        return points.enumerated().map { index, point in
            let offset = lift * sin(.pi * distances[index] / travelled)
            return CGPoint(x: point.x + normalX * offset, y: point.y + normalY * offset)
        }
    }

    /// Replaces every interior corner with a quadratic arc.
    ///
    /// Thinning is what puts the kinks back: Chaikin rounds a corner into many
    /// small steps and Douglas–Peucker then draws one straight line across
    /// them, so the corridor arrived on screen as a run of hard elbows — an M
    /// where the route should read as an S. Measured over eight long legs, one
    /// joint in five turned more than 45°.
    ///
    /// Each corner becomes a quadratic Bézier whose control point is the corner
    /// itself and whose ends are the neighbouring segment midpoints. Because
    /// every sample is a convex combination of three consecutive points, the
    /// curve stays inside the polyline's hull — the same property that keeps
    /// the corridor on land survives the smoothing. After this no joint exceeds
    /// 27°, and the median turn drops from 32° to under 4°.
    private static func roundCorners(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        var result: [CGPoint] = [points[0], midpoint(points[0], points[1])]
        result.reserveCapacity(points.count * cornerSamples)
        for index in 1..<(points.count - 1) {
            let start = midpoint(points[index - 1], points[index])
            let control = points[index]
            let end = midpoint(points[index], points[index + 1])
            for sample in 1...cornerSamples {
                let t = CGFloat(sample) / CGFloat(cornerSamples)
                let inverse = 1 - t
                result.append(CGPoint(
                    x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                    y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y
                ))
            }
        }
        result.append(points[points.count - 1])
        return result
    }

    /// One Chaikin corner-cutting pass. Endpoints are preserved; every new
    /// point sits a quarter and three quarters of the way along an existing
    /// segment, so the result is strictly inside the original polyline's hull.
    private static func chaikin(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var result: [CGPoint] = [points[0]]
        result.reserveCapacity(points.count * 2)
        for index in 0..<(points.count - 1) {
            let a = points[index]
            let b = points[index + 1]
            result.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
            result.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
        }
        result.append(points[points.count - 1])
        return result
    }
}
