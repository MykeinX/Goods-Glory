//
//  GameCatalog.swift
//  Goods&Glory
//
//  Validated, read-only content catalog. Loads bundled JSON, verifies
//  cross-references and physical sanity, and provides the road graph.
//  A broken catalog fails loudly at launch; it is never silently ignored.
//

import Foundation

struct GameCatalog: Sendable {
    let cities: [CityDefinition]
    let networkNodes: [NetworkNodeDefinition]
    let roads: [RoadDefinition]
    let vehicleTypes: [VehicleTypeDefinition]
    let products: [ProductDefinition]
    let cityMarkets: [CityMarketProfile]
    let economy: EconomyConfig
    /// Derived trading firms: one per city-market supply/demand entry.
    let firms: [Firm]
    /// Derived persistent freight lanes — the world's standing demand.
    let lanes: [FreightLane]

    let citiesByID: [CityID: CityDefinition]
    let firmsByID: [FirmID: Firm]
    let lanesByID: [LaneID: FreightLane]
    let networkNodesByID: [RoadNodeID: NetworkNodeDefinition]
    let roadsByID: [RoadID: RoadDefinition]
    let vehicleTypesByID: [VehicleTypeID: VehicleTypeDefinition]
    let productsByID: [ProductID: ProductDefinition]
    let cityMarketsByID: [CityID: CityMarketProfile]
    /// Adjacency list, neighbor lists sorted by node and road ID for determinism.
    let adjacency: [RoadNodeID: [RoadEdge]]
    /// All-pairs road distances between cities. Absent pairs are on different
    /// road networks. Built once at load: one Dijkstra per city.
    let cityDistances: [CityID: [CityID: Double]]

    struct RoadEdge: Sendable {
        let neighbor: RoadNodeID
        let distanceKm: Double
        let traversal: RoadTraversal
    }

    struct RouteFrontier: Sendable {
        struct Entry: Sendable {
            let node: RoadNodeID
            let distance: Double
        }

        var entries: [Entry] = []

        mutating func insert(node: RoadNodeID, distance: Double) {
            entries.append(Entry(node: node, distance: distance))
            var childIndex = entries.count - 1
            while childIndex > 0 {
                let parentIndex = (childIndex - 1) / 2
                guard Self.precedes(entries[childIndex], entries[parentIndex]) else { break }
                entries.swapAt(childIndex, parentIndex)
                childIndex = parentIndex
            }
        }

        mutating func removeMinimum() -> (node: RoadNodeID, distance: Double)? {
            guard !entries.isEmpty else { return nil }
            if entries.count == 1 {
                let entry = entries.removeLast()
                return (entry.node, entry.distance)
            }

            entries.swapAt(0, entries.count - 1)
            let minimum = entries.removeLast()
            var parentIndex = 0
            while true {
                let leftChildIndex = parentIndex * 2 + 1
                guard leftChildIndex < entries.count else { break }
                let rightChildIndex = leftChildIndex + 1
                var smallerChildIndex = leftChildIndex
                if rightChildIndex < entries.count,
                   Self.precedes(entries[rightChildIndex], entries[leftChildIndex]) {
                    smallerChildIndex = rightChildIndex
                }
                guard Self.precedes(entries[smallerChildIndex], entries[parentIndex]) else { break }
                entries.swapAt(parentIndex, smallerChildIndex)
                parentIndex = smallerChildIndex
            }
            return (minimum.node, minimum.distance)
        }

        static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
            lhs.distance == rhs.distance
                ? lhs.node.rawValue < rhs.node.rawValue
                : lhs.distance < rhs.distance
        }
    }

    var starterCities: [CityDefinition] { cities.filter(\.isStarterCity) }

    func city(_ id: CityID) -> CityDefinition? { citiesByID[id] }
    func networkNode(_ id: RoadNodeID) -> NetworkNodeDefinition? { networkNodesByID[id] }
    func vehicleType(_ id: VehicleTypeID) -> VehicleTypeDefinition? { vehicleTypesByID[id] }
    func product(_ id: ProductID) -> ProductDefinition? { productsByID[id] }
    func cityMarket(_ id: CityID) -> CityMarketProfile? { cityMarketsByID[id] }
    func firm(_ id: FirmID) -> Firm? { firmsByID[id] }

    func firms(in city: CityID) -> [Firm] {
        firms.filter { $0.cityID == city }
    }

    /// The firm shipping `product` out of `city`, if the market supplies it.
    func supplierFirm(city: CityID, product: ProductID) -> Firm? {
        firmsByID[Self.firmID(city: city, product: product, role: .supplier)]
    }

    /// The firm receiving `product` in `city`, if the market demands it.
    func receiverFirm(city: CityID, product: ProductID) -> Firm? {
        firmsByID[Self.firmID(city: city, product: product, role: .receiver)]
    }

    static func firmID(city: CityID, product: ProductID, role: FirmRole) -> FirmID {
        FirmID("\(city.rawValue).\(product.rawValue).\(role.rawValue)")
    }

    func lane(_ id: LaneID) -> FreightLane? { lanesByID[id] }

    /// Outbound lanes of a city, ordered by rate descending (derivation order).
    func lanes(from city: CityID) -> [FreightLane] {
        lanes.filter { $0.originCityID == city }
    }

    func lanes(to city: CityID) -> [FreightLane] {
        lanes.filter { $0.destinationCityID == city }
    }
}
