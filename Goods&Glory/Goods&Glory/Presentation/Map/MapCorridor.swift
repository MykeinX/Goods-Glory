//
//  MapCorridor.swift
//  Goods&Glory
//
//  Shared schematic land-road geometry. Domain routing remains on the precise
//  data-driven road graph; SpriteKit consumes a stable, low-bend atlas derived
//  from that graph once per catalog.
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
/// Degree-two junction chains are simplified and converted to clean
/// horizontal, vertical and diagonal runs. Every `RoadID` receives one shared
/// piece of that geometry, so overlapping routes and all vehicles use exactly
/// the same line instead of generating a curve per vehicle.
@MainActor
final class MapCorridorCache {
    static let shared = MapCorridorCache()

    private static let guideToleranceKm: CGFloat = 125
    private static let directAngleTolerance: CGFloat = 7 * .pi / 180

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

    private struct Edge {
        let road: RoadDefinition
        let neighbor: RoadNodeID
    }

    private struct Layout {
        let roadPoints: [RoadID: [CGPoint]]
    }

    private var signature: Signature?
    private var layout: Layout?
    private var corridorCache: [Key: MapCorridor] = [:]
    private var roadIDCache: [Key: [RoadID]] = [:]

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
            guard var road = layout?.roadPoints[traversal.roadID] else { continue }
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
        return layout?.roadPoints[roadID]
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
        let nextSignature = Signature(catalog: catalog)
        guard signature != nextSignature || layout == nil else { return }
        signature = nextSignature
        corridorCache.removeAll(keepingCapacity: true)
        roadIDCache.removeAll(keepingCapacity: true)
        layout = Self.buildLayout(catalog: catalog, projection: projection)
    }

    private static func buildLayout(
        catalog: GameCatalog,
        projection: MapProjection
    ) -> Layout {
        var adjacency: [RoadNodeID: [Edge]] = [:]
        adjacency.reserveCapacity(catalog.networkNodes.count)
        for road in catalog.roads {
            adjacency[road.from, default: []].append(Edge(road: road, neighbor: road.to))
            adjacency[road.to, default: []].append(Edge(road: road, neighbor: road.from))
        }
        for nodeID in adjacency.keys {
            adjacency[nodeID]?.sort { $0.road.id.rawValue < $1.road.id.rawValue }
        }

        let anchors = Set(catalog.networkNodes.compactMap { node -> RoadNodeID? in
            let degree = adjacency[node.id]?.count ?? 0
            return node.kind == .city || degree != 2 ? node.id : nil
        })
        var visited = Set<RoadID>()
        var result: [RoadID: [CGPoint]] = [:]
        result.reserveCapacity(catalog.roads.count)

        let sortedAnchors = anchors.sorted { $0.rawValue < $1.rawValue }
        for anchor in sortedAnchors {
            for edge in adjacency[anchor] ?? [] where !visited.contains(edge.road.id) {
                let chain = walk(
                    from: anchor,
                    firstEdge: edge,
                    anchors: anchors,
                    adjacency: adjacency,
                    visited: &visited
                )
                assign(chain: chain, catalog: catalog, projection: projection, into: &result)
            }
        }

        // A disconnected ring can contain only degree-two junctions and
        // therefore no natural anchor. It is still deterministic and shared.
        for road in catalog.roads.sorted(by: { $0.id.rawValue < $1.id.rawValue })
        where !visited.contains(road.id) {
            let edge = Edge(road: road, neighbor: road.to)
            let chain = walk(
                from: road.from,
                firstEdge: edge,
                anchors: [road.from],
                adjacency: adjacency,
                visited: &visited
            )
            assign(chain: chain, catalog: catalog, projection: projection, into: &result)
        }

        return Layout(roadPoints: result)
    }

    private static func walk(
        from start: RoadNodeID,
        firstEdge: Edge,
        anchors: Set<RoadNodeID>,
        adjacency: [RoadNodeID: [Edge]],
        visited: inout Set<RoadID>
    ) -> (nodes: [RoadNodeID], roads: [RoadDefinition]) {
        var nodes = [start]
        var roads: [RoadDefinition] = []
        var edge = firstEdge

        while !visited.contains(edge.road.id) {
            visited.insert(edge.road.id)
            roads.append(edge.road)
            let next = edge.neighbor
            nodes.append(next)
            if anchors.contains(next) { break }
            guard let following = adjacency[next]?.first(where: {
                !visited.contains($0.road.id)
            }) else { break }
            edge = following
        }
        return (nodes, roads)
    }

    private static func assign(
        chain: (nodes: [RoadNodeID], roads: [RoadDefinition]),
        catalog: GameCatalog,
        projection: MapProjection,
        into output: inout [RoadID: [CGPoint]]
    ) {
        guard chain.nodes.count == chain.roads.count + 1,
              chain.nodes.count >= 2 else { return }
        let raw = chain.nodes.compactMap {
            catalog.networkNode($0).map { projection.point(for: $0.coordinate) }
        }
        guard raw.count == chain.nodes.count else { return }

        let schematic = schematicPolyline(raw)
        let schematicLengths = cumulativeLengths(schematic)
        let schematicTotal = schematicLengths.last ?? 0
        let physicalTotal = chain.roads.reduce(0) { $0 + max(0, $1.distanceKm) }
        guard schematicTotal > 0, physicalTotal > 0 else { return }

        var physicalStart = 0.0
        for (index, road) in chain.roads.enumerated() {
            let physicalEnd = physicalStart + max(0, road.distanceKm)
            let startFraction = CGFloat(physicalStart / physicalTotal)
            let endFraction = CGFloat(physicalEnd / physicalTotal)
            var section = slice(
                schematic,
                lengths: schematicLengths,
                from: startFraction,
                to: endFraction
            )
            let walkedForward = road.from == chain.nodes[index]
                && road.to == chain.nodes[index + 1]
            if !walkedForward { section.reverse() }
            output[road.id] = section
            physicalStart = physicalEnd
        }
    }

    private static func schematicPolyline(_ points: [CGPoint]) -> [CGPoint] {
        let guides = MapPathSimplifier.simplify(points, tolerance: guideToleranceKm)
        guard guides.count >= 2 else { return points }
        var result = [guides[0]]
        for index in 1..<guides.count {
            append(octilinearLeg(from: guides[index - 1], to: guides[index]), to: &result)
        }
        return roundedPolyline(MapCorridor(points: result).points)
    }

    /// Rounds the shared metro geometry itself, so vehicles and route strokes
    /// follow the same soft bends instead of only painting rounded line joins.
    private static func roundedPolyline(
        _ points: [CGPoint],
        radius: CGFloat = 90,
        samplesPerCorner: Int = 5
    ) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        var result = [points[0]]
        result.reserveCapacity(points.count * (samplesPerCorner + 1))

        for index in 1..<(points.count - 1) {
            let previous = points[index - 1]
            let corner = points[index]
            let next = points[index + 1]
            let incomingLength = corner.distance(to: previous)
            let outgoingLength = corner.distance(to: next)
            guard incomingLength > 0.01, outgoingLength > 0.01 else { continue }

            let offset = min(radius, incomingLength * 0.22, outgoingLength * 0.22)
            let inlet = corner.interpolated(
                to: previous,
                fraction: offset / incomingLength
            )
            let outlet = corner.interpolated(
                to: next,
                fraction: offset / outgoingLength
            )
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

        result.append(points[points.count - 1])
        return MapCorridor(points: result).points
    }

    /// One clean bend chosen from the eight metro-map directions.
    private static func octilinearLeg(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let delta = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let distance = hypot(delta.x, delta.y)
        guard distance > 0.01 else { return [start, end] }

        let angle = atan2(delta.y, delta.x)
        let snappedAngle = (angle / (.pi / 4)).rounded() * (.pi / 4)
        if abs(Self.angleDifference(angle, snappedAngle)) <= directAngleTolerance {
            return [start, end]
        }

        let diagonal = CGFloat(1 / sqrt(2.0))
        let directions = [
            CGPoint(x: 1, y: 0), CGPoint(x: diagonal, y: diagonal),
            CGPoint(x: 0, y: 1), CGPoint(x: -diagonal, y: diagonal),
            CGPoint(x: -1, y: 0), CGPoint(x: -diagonal, y: -diagonal),
            CGPoint(x: 0, y: -1), CGPoint(x: diagonal, y: -diagonal)
        ]

        var best: (point: CGPoint, score: CGFloat)?
        for incoming in directions {
            for outgoing in directions {
                let determinant = incoming.x * outgoing.y - incoming.y * outgoing.x
                guard abs(determinant) > 0.001 else { continue }
                let firstLength = (delta.x * outgoing.y - delta.y * outgoing.x) / determinant
                let secondLength = (incoming.x * delta.y - incoming.y * delta.x) / determinant
                guard firstLength > 0, secondLength > 0 else { continue }
                let pathLength = firstLength + secondLength
                guard pathLength <= distance * 1.55 else { continue }
                let bend = CGPoint(
                    x: start.x + incoming.x * firstLength,
                    y: start.y + incoming.y * firstLength
                )
                let balancePenalty = abs(firstLength - secondLength) * 0.035
                let score = pathLength + balancePenalty
                if best == nil || score < best!.score {
                    best = (bend, score)
                }
            }
        }
        return best.map { [start, $0.point, end] } ?? [start, end]
    }

    private static func cumulativeLengths(_ points: [CGPoint]) -> [CGFloat] {
        guard !points.isEmpty else { return [] }
        var result: [CGFloat] = [0]
        result.reserveCapacity(points.count)
        for index in 1..<points.count {
            result.append(result[index - 1] + points[index].distance(to: points[index - 1]))
        }
        return result
    }

    private static func slice(
        _ points: [CGPoint],
        lengths: [CGFloat],
        from startFraction: CGFloat,
        to endFraction: CGFloat
    ) -> [CGPoint] {
        guard let total = lengths.last, total > 0 else {
            return Array(points.prefix(2))
        }
        let startDistance = startFraction.clamped(to: 0...1) * total
        let endDistance = endFraction.clamped(to: 0...1) * total
        var result = [point(on: points, lengths: lengths, distance: startDistance)]
        for index in points.indices where lengths[index] > startDistance && lengths[index] < endDistance {
            result.append(points[index])
        }
        result.append(point(on: points, lengths: lengths, distance: endDistance))
        return result
    }

    private static func point(
        on points: [CGPoint],
        lengths: [CGFloat],
        distance: CGFloat
    ) -> CGPoint {
        guard points.count > 1 else { return points.first ?? .zero }
        let target = distance.clamped(to: 0...(lengths.last ?? 0))
        var index = 0
        while index + 1 < lengths.count, lengths[index + 1] < target { index += 1 }
        guard index + 1 < points.count else { return points.last ?? .zero }
        let span = lengths[index + 1] - lengths[index]
        let fraction = span > 0 ? (target - lengths[index]) / span : 0
        return points[index].interpolated(to: points[index + 1], fraction: fraction)
    }

    private static func append(_ points: [CGPoint], to result: inout [CGPoint]) {
        guard !points.isEmpty else { return }
        if let last = result.last, last.distance(to: points[0]) < 0.01 {
            result.append(contentsOf: points.dropFirst())
        } else {
            result.append(contentsOf: points)
        }
    }

    private static func angleDifference(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        atan2(sin(lhs - rhs), cos(lhs - rhs))
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
