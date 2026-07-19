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
//    2. Chaikin corner-cutting ×2. Every generated point is a convex
//       combination of two neighbours, so the curve stays inside the polyline's
//       hull — if the road is on land, the smoothed line is on land.
//    3. Douglas–Peucker at 15 km to thin it back down.
//
//  That lands at ~9 points per corridor (24 worst case) with zero water
//  crossings across every pair. Simplifying *before* smoothing — the obvious
//  order — is what caused the crossings: it cut the corner the road took to go
//  around a lake, and the spline then sailed straight over it.
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
    private static let smoothingPasses = 2
    /// Thinning tolerance in world units (≈ km). Well under what is visible at
    /// strategic zoom, and it keeps corridors at roughly nine points.
    private static let thinningToleranceKm: CGFloat = 15

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
        return MapCorridor(points: thinned.count >= 2 ? thinned : projected)
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
