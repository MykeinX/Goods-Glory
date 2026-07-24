//
//  MapCorridor.swift
//  Goods&Glory
//
//  Shared Mini Metro-style road geometry. The octilinear polylines are baked
//  into road_geometry.json by generate_trade_network.py against the board's
//  land mask, so this only projects and joins them. Every RoadID hands out one
//  shared polyline: overlapping routes never thicken or fan into parallel
//  tracks, and a vehicle always rides exactly the line drawn under it.
//

import CoreGraphics
import Foundation

/// Ordered points plus an arc-length table used to place a vehicle at a
/// fraction of its journey.
struct MapCorridor: Equatable {
    let points: [CGPoint]
    private let lengths: [CGFloat]

    init(points: [CGPoint]) {
        let cleaned: [CGPoint]
        switch points.count {
        case 0: cleaned = [.zero, .zero]
        case 1: cleaned = [points[0], points[0]]
        default: cleaned = Self.removingRedundantPoints(points)
        }

        var lengths: [CGFloat] = [0]
        lengths.reserveCapacity(cleaned.count)
        var total: CGFloat = 0
        for index in 1..<cleaned.count {
            total += cleaned[index].distance(to: cleaned[index - 1])
            lengths.append(total)
        }
        self.points = cleaned
        self.lengths = lengths
    }

    static func direct(from start: CGPoint, to end: CGPoint) -> MapCorridor {
        MapCorridor(points: [start, end])
    }

    var totalLength: CGFloat { lengths.last ?? 0 }

    func position(at progress: CGFloat) -> CGPoint {
        let (index, fraction) = locate(progress)
        guard index + 1 < points.count else { return points[index] }
        return points[index].interpolated(to: points[index + 1], fraction: fraction)
    }

    func heading(at progress: CGFloat) -> CGFloat {
        let (index, _) = locate(progress)
        let start = points[max(0, min(index, points.count - 2))]
        let end = points[max(1, min(index + 1, points.count - 1))]
        return atan2(end.y - start.y, end.x - start.x)
    }

    private func locate(_ progress: CGFloat) -> (index: Int, fraction: CGFloat) {
        guard points.count > 1, totalLength > 0 else { return (0, 0) }
        let target = progress.clamped(to: 0...1) * totalLength
        var low = 0
        var high = lengths.count - 1
        while low + 1 < high {
            let middle = (low + high) / 2
            if lengths[middle] <= target {
                low = middle
            } else {
                high = middle
            }
        }
        let span = lengths[low + 1] - lengths[low]
        return span > 0 ? (low, (target - lengths[low]) / span) : (low, 0)
    }

    private static func removingRedundantPoints(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            if let last = result.last, point.distance(to: last) < 0.01 { continue }
            while result.count >= 2 {
                let a = result[result.count - 2]
                let b = result[result.count - 1]
                let cross = abs((b.x - a.x) * (point.y - b.y) - (b.y - a.y) * (point.x - b.x))
                let scale = max(a.distance(to: b) + b.distance(to: point), 1)
                guard cross / scale < 0.01 else { break }
                result.removeLast()
            }
            result.append(point)
        }
        return result.count >= 2 ? result : [points[0], points[0]]
    }
}

/// Session atlas for the land network.
///
/// Projecting the baked polylines and resolving shortest routes are both pure
/// functions of immutable data, so both are done once and then shared by every
/// map surface.
@MainActor
final class MapCorridorCache {
    static let shared = MapCorridorCache()

    private struct Signature: Equatable {
        let nodeCount: Int
        let roadCount: Int
        let firstNode: RoadNodeID?
        let lastNode: RoadNodeID?
        let firstRoad: RoadID?
        let lastRoad: RoadID?

        init(catalog: GameCatalog) {
            nodeCount = catalog.networkNodes.count
            roadCount = catalog.roads.count
            firstNode = catalog.networkNodes.first?.id
            lastNode = catalog.networkNodes.last?.id
            firstRoad = catalog.roads.first?.id
            lastRoad = catalog.roads.last?.id
        }
    }

    private struct Key: Hashable {
        let origin: CityID
        let destination: CityID
    }

    private let geometry: MapRoadGeometry
    private var signature: Signature?
    private var roadPoints: [RoadID: [CGPoint]]?
    private var corridorCache: [Key: MapCorridor] = [:]
    private var roadIDCache: [Key: [RoadID]] = [:]

    init(geometry: MapRoadGeometry = .bundled) {
        self.geometry = geometry
    }

    func corridor(
        from origin: CityID,
        to destination: CityID,
        catalog: GameCatalog,
        projection: MapProjection
    ) -> MapCorridor {
        prepare(catalog: catalog, projection: projection)
        let key = Key(origin: origin, destination: destination)
        if let cached = corridorCache[key] { return cached }

        let start = catalog.city(origin).map(projection.point(for:)) ?? .zero
        let end = catalog.city(destination).map(projection.point(for:)) ?? .zero
        guard origin != destination,
              let route = catalog.shortestRoute(from: origin, to: destination) else {
            let direct = MapCorridor.direct(from: start, to: end)
            corridorCache[key] = direct
            return direct
        }

        var points: [CGPoint] = []
        for traversal in route.traversals {
            guard var road = roadPoints?[traversal.roadID] else { continue }
            if traversal.direction == .reverse { road.reverse() }
            Self.append(road, to: &points)
        }
        let corridor = points.count >= 2
            ? MapCorridor(points: points)
            : MapCorridor.direct(from: start, to: end)
        corridorCache[key] = corridor
        return corridor
    }

    func points(
        for roadID: RoadID,
        catalog: GameCatalog,
        projection: MapProjection
    ) -> [CGPoint]? {
        prepare(catalog: catalog, projection: projection)
        return roadPoints?[roadID]
    }

    func roadIDs(
        from origin: CityID,
        to destination: CityID,
        catalog: GameCatalog,
        projection: MapProjection
    ) -> [RoadID] {
        prepare(catalog: catalog, projection: projection)
        let key = Key(origin: origin, destination: destination)
        if let cached = roadIDCache[key] { return cached }
        let value = catalog.shortestRoute(from: origin, to: destination)?
            .traversals.map(\.roadID) ?? []
        roadIDCache[key] = value
        return value
    }

    private func prepare(catalog: GameCatalog, projection: MapProjection) {
        if roadPoints == nil {
            roadPoints = Dictionary(
                geometry.roads.map { ($0.id, $0.points.map(projection.point(for:))) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        // Route lookups are per catalog; the baked geometry is not.
        let nextSignature = Signature(catalog: catalog)
        guard signature != nextSignature else { return }
        signature = nextSignature
        corridorCache.removeAll(keepingCapacity: true)
        roadIDCache.removeAll(keepingCapacity: true)
    }

    private static func append(_ points: [CGPoint], to result: inout [CGPoint]) {
        guard !points.isEmpty else { return }
        if let last = result.last, last.distance(to: points[0]) < 0.01 {
            result.append(contentsOf: points.dropFirst())
        } else {
            result.append(contentsOf: points)
        }
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }

    func interpolated(to other: CGPoint, fraction: CGFloat) -> CGPoint {
        CGPoint(
            x: x + (other.x - x) * fraction,
            y: y + (other.y - y) * fraction
        )
    }
}
