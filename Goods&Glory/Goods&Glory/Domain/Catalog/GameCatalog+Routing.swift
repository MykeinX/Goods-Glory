//
//  GameCatalog+Routing.swift
//  Goods&Glory
//
//  The road graph: deterministic shortest paths and reachability. One
//  canonical graph, shared by routing and by what the map draws.
//

import Foundation

extension GameCatalog {
    // MARK: - Routing

    struct Route: Sendable {
        /// Ordered graph nodes from origin to destination, inclusive.
        let nodes: [RoadNodeID]
        /// Ordered city IDs encountered along the node path, including both endpoints.
        let cities: [CityID]
        /// Ordered road traversals from origin to destination.
        let traversals: [RoadTraversal]
        let distanceKm: Double
    }

    /// Deterministic Dijkstra over the road graph.
    func shortestRoute(from origin: CityID, to destination: CityID) -> Route? {
        guard let originNode = citiesByID[origin]?.roadNodeID,
              let destinationNode = citiesByID[destination]?.roadNodeID else { return nil }
        if origin == destination {
            return Route(nodes: [originNode], cities: [origin], traversals: [], distanceKm: 0)
        }

        var distances: [RoadNodeID: Double] = [originNode: 0]
        var previous: [RoadNodeID: (node: RoadNodeID, traversal: RoadTraversal)] = [:]
        var visited: Set<RoadNodeID> = []
        var frontier = RouteFrontier()
        frontier.insert(node: originNode, distance: 0)

        while let current = frontier.removeMinimum() {
            if visited.contains(current.node) { continue }
            visited.insert(current.node)
            if current.node == destinationNode { break }

            for edge in adjacency[current.node] ?? [] {
                let candidate = current.distance + edge.distanceKm
                if candidate < distances[edge.neighbor] ?? .infinity {
                    distances[edge.neighbor] = candidate
                    previous[edge.neighbor] = (current.node, edge.traversal)
                    frontier.insert(node: edge.neighbor, distance: candidate)
                }
            }
        }

        guard let total = distances[destinationNode], visited.contains(destinationNode) else { return nil }
        var cursor = destinationNode
        var reversedNodePath: [RoadNodeID] = [cursor]
        var reversedTraversals: [RoadTraversal] = []
        while let prior = previous[cursor] {
            reversedNodePath.append(prior.node)
            reversedTraversals.append(prior.traversal)
            cursor = prior.node
        }
        let nodePath = Array(reversedNodePath.reversed())
        let traversals = Array(reversedTraversals.reversed())
        let cityPath = nodePath.compactMap { networkNodesByID[$0]?.cityID }
        return Route(nodes: nodePath, cities: cityPath, traversals: traversals, distanceKm: total)
    }

    /// Cities actually reachable by road from the given city, excluding itself.
    ///
    /// This used to return every city in the catalog. That was harmless while
    /// the world was one country; with America and Eurasia on separate road
    /// networks it would offer freight nobody can haul.
    func reachableCities(from origin: CityID) -> [CityID] {
        guard citiesByID[origin] != nil else { return [] }
        return (cityDistances[origin] ?? [:]).keys
            .filter { $0 != origin }
            .sorted { $0.rawValue < $1.rawValue }
    }

    /// Road distance between two cities, or nil when no road connects them.
    ///
    /// Backed by an all-pairs table built once at load. The offer generator
    /// weighs every candidate destination by distance, so without this it ran a
    /// Dijkstra per city per generated offer — 70 of them per offer at world
    /// scale, over a 731-node graph.
    func roadDistanceKm(from origin: CityID, to destination: CityID) -> Double? {
        cityDistances[origin]?[destination]
    }

    /// Geographically closest connected cities, with stable ID tie-breaking.
    func nearestCities(from origin: CityID, limit: Int) -> [CityID] {
        guard limit > 0, let originCity = citiesByID[origin] else { return [] }
        return cities
            .filter { $0.id != origin }
            .sorted {
                let leftDistance = Self.geographicDistanceKm(originCity.coordinate, $0.coordinate)
                let rightDistance = Self.geographicDistanceKm(originCity.coordinate, $1.coordinate)
                return leftDistance == rightDistance
                    ? $0.id.rawValue < $1.id.rawValue
                    : leftDistance < rightDistance
            }
            .prefix(limit)
            .map(\.id)
    }

}
