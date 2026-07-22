//
//  GameCatalog+Loading.swift
//  Goods&Glory
//
//  Decoding bundled JSON and building the identity indices. A broken
//  catalog fails loudly here rather than misbehaving later.
//

import Foundation

extension GameCatalog {
    // MARK: - Loading

    enum CatalogError: Error, CustomStringConvertible {
        case missingResource(String)
        case validationFailure(String)

        var description: String {
            switch self {
            case .missingResource(let name): "Missing catalog resource: \(name)"
            case .validationFailure(let reason): "Catalog validation failed: \(reason)"
            }
        }
    }

    static func load(from bundle: Bundle) throws -> GameCatalog {
        func decode<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
            guard let url = bundle.url(forResource: resource, withExtension: "json") else {
                throw CatalogError.missingResource(resource)
            }
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        }

        return try GameCatalog(
            cities: decode([CityDefinition].self, resource: "cities"),
            networkNodes: decode([NetworkNodeDefinition].self, resource: "road_nodes"),
            roads: decode([RoadDefinition].self, resource: "roads"),
            vehicleTypes: decode([VehicleTypeDefinition].self, resource: "vehicle_types"),
            products: decode([ProductDefinition].self, resource: "products"),
            cityMarkets: decode([CityMarketProfile].self, resource: "city_markets"),
            economy: decode(EconomyConfig.self, resource: "economy"),
            firmNames: decode(FirmNamePools.self, resource: "firm_names")
        )
    }

    init(
        cities: [CityDefinition],
        networkNodes: [NetworkNodeDefinition],
        roads: [RoadDefinition],
        vehicleTypes: [VehicleTypeDefinition],
        products: [ProductDefinition],
        cityMarkets: [CityMarketProfile],
        economy: EconomyConfig,
        firmNames: FirmNamePools = .fallback
    ) throws {
        self.cities = cities
        self.networkNodes = networkNodes
        self.roads = roads
        self.vehicleTypes = vehicleTypes
        self.products = products
        self.cityMarkets = cityMarkets
        self.economy = economy
        self.firms = Self.deriveFirms(cities: cities, cityMarkets: cityMarkets, pools: firmNames)
        self.firmsByID = try Self.uniqueIndex(firms, id: \.id, label: "firm")

        self.citiesByID = try Self.uniqueIndex(cities, id: \.id, label: "city")
        self.networkNodesByID = try Self.uniqueIndex(networkNodes, id: \.id, label: "road node")
        self.roadsByID = try Self.uniqueIndex(roads, id: \.id, label: "road")
        self.vehicleTypesByID = try Self.uniqueIndex(vehicleTypes, id: \.id, label: "vehicle type")
        self.productsByID = try Self.uniqueIndex(products, id: \.id, label: "product")
        self.cityMarketsByID = try Self.uniqueIndex(cityMarkets, id: \.cityID, label: "city market")

        try Self.validateNetworkNodes(
            networkNodes,
            citiesByID: citiesByID,
            networkNodesByID: networkNodesByID
        )

        var adjacency: [RoadNodeID: [RoadEdge]] = [:]
        for road in roads {
            guard networkNodesByID[road.from] != nil, networkNodesByID[road.to] != nil else {
                throw CatalogError.validationFailure("road \(road.id) references unknown road node")
            }
            guard road.from != road.to else {
                throw CatalogError.validationFailure("road \(road.id) is a self-loop")
            }
            guard road.distanceKm.isFinite, road.distanceKm > 0 else {
                throw CatalogError.validationFailure("road \(road.id) has non-positive distance")
            }
            adjacency[road.from, default: []].append(RoadEdge(
                neighbor: road.to,
                distanceKm: road.distanceKm,
                traversal: RoadTraversal(roadID: road.id, direction: .forward)
            ))
            adjacency[road.to, default: []].append(RoadEdge(
                neighbor: road.from,
                distanceKm: road.distanceKm,
                traversal: RoadTraversal(roadID: road.id, direction: .reverse)
            ))
        }
        for key in adjacency.keys {
            adjacency[key]?.sort {
                if $0.neighbor != $1.neighbor {
                    return $0.neighbor.rawValue < $1.neighbor.rawValue
                }
                return $0.traversal.roadID.rawValue < $1.traversal.roadID.rawValue
            }
        }
        self.adjacency = adjacency
        self.cityDistances = Self.allPairsCityDistances(
            cities: cities,
            networkNodes: networkNodes,
            adjacency: adjacency
        )

        self.lanes = Self.deriveLanes(
            cities: cities,
            cityMarketsByID: cityMarketsByID,
            economy: economy,
            cityDistances: cityDistances
        )
        self.lanesByID = try Self.uniqueIndex(lanes, id: \.id, label: "freight lane")

        try validate()
    }

    /// One Dijkstra per city over the shared road graph, keeping only the
    /// distances to other cities' entry nodes.
    static func allPairsCityDistances(
        cities: [CityDefinition],
        networkNodes: [NetworkNodeDefinition],
        adjacency: [RoadNodeID: [RoadEdge]]
    ) -> [CityID: [CityID: Double]] {
        var cityByNode: [RoadNodeID: CityID] = [:]
        cityByNode.reserveCapacity(cities.count)
        for city in cities { cityByNode[city.roadNodeID] = city.id }

        var result: [CityID: [CityID: Double]] = [:]
        result.reserveCapacity(cities.count)
        for city in cities {
            var distances: [RoadNodeID: Double] = [city.roadNodeID: 0]
            var visited: Set<RoadNodeID> = []
            var frontier = RouteFrontier()
            frontier.insert(node: city.roadNodeID, distance: 0)
            var reached: [CityID: Double] = [:]
            while let current = frontier.removeMinimum() {
                if visited.contains(current.node) { continue }
                visited.insert(current.node)
                if let reachedCity = cityByNode[current.node] {
                    reached[reachedCity] = current.distance
                }
                for edge in adjacency[current.node] ?? [] {
                    let candidate = current.distance + edge.distanceKm
                    if candidate < distances[edge.neighbor] ?? .infinity {
                        distances[edge.neighbor] = candidate
                        frontier.insert(node: edge.neighbor, distance: candidate)
                    }
                }
            }
            result[city.id] = reached
        }
        return result
    }

}
