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

    private let citiesByID: [CityID: CityDefinition]
    private let firmsByID: [FirmID: Firm]
    private let networkNodesByID: [RoadNodeID: NetworkNodeDefinition]
    private let roadsByID: [RoadID: RoadDefinition]
    private let vehicleTypesByID: [VehicleTypeID: VehicleTypeDefinition]
    private let productsByID: [ProductID: ProductDefinition]
    private let cityMarketsByID: [CityID: CityMarketProfile]
    /// Adjacency list, neighbor lists sorted by node and road ID for determinism.
    private let adjacency: [RoadNodeID: [RoadEdge]]
    /// All-pairs road distances between cities. Absent pairs are on different
    /// road networks. Built once at load: one Dijkstra per city.
    private let cityDistances: [CityID: [CityID: Double]]

    private struct RoadEdge: Sendable {
        let neighbor: RoadNodeID
        let distanceKm: Double
        let traversal: RoadTraversal
    }

    private struct RouteFrontier: Sendable {
        private struct Entry: Sendable {
            let node: RoadNodeID
            let distance: Double
        }

        private var entries: [Entry] = []

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

        private static func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
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

        try validate()
    }

    /// One Dijkstra per city over the shared road graph, keeping only the
    /// distances to other cities' entry nodes.
    private static func allPairsCityDistances(
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

    // MARK: - Firm derivation

    /// Deterministically turns every city-market supply/demand entry into a
    /// named trading firm. No authored firm data and no save state: the same
    /// catalog always yields the same firms.
    private static func deriveFirms(
        cities: [CityDefinition],
        cityMarkets: [CityMarketProfile],
        pools: FirmNamePools
    ) -> [Firm] {
        guard !pools.stems.isEmpty else { return [] }
        var firms: [Firm] = []
        for city in cities.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard let market = cityMarkets.first(where: { $0.cityID == city.id }) else { continue }
            var usedStems: Set<String> = []

            func stem(for product: ProductID, role: FirmRole) -> String {
                let hash = SeedDerivation.seed(
                    0, "firm_stem",
                    .string(city.id.rawValue), .string(product.rawValue), .string(role.rawValue)
                )
                var index = Int(hash % UInt64(pools.stems.count))
                // Linear probe so firm names stay unique within one city.
                for _ in 0..<pools.stems.count {
                    let candidate = pools.stems[index]
                    if !usedStems.contains(candidate) {
                        usedStems.insert(candidate)
                        return candidate
                    }
                    index = (index + 1) % pools.stems.count
                }
                return pools.stems[index]
            }

            func suffix(for product: ProductID, role: FirmRole, from list: [String]) -> String {
                guard !list.isEmpty else { return "" }
                let hash = SeedDerivation.seed(
                    0, "firm_suffix",
                    .string(city.id.rawValue), .string(product.rawValue), .string(role.rawValue)
                )
                return list[Int(hash % UInt64(list.count))]
            }

            for entry in market.supply {
                let name = "\(stem(for: entry.productID, role: .supplier)) \(suffix(for: entry.productID, role: .supplier, from: pools.supplierSuffixes))"
                firms.append(Firm(
                    id: firmID(city: city.id, product: entry.productID, role: .supplier),
                    cityID: city.id,
                    productID: entry.productID,
                    role: .supplier,
                    name: name.trimmingCharacters(in: .whitespaces)
                ))
            }
            for entry in market.demand {
                let name = "\(stem(for: entry.productID, role: .receiver)) \(suffix(for: entry.productID, role: .receiver, from: pools.receiverSuffixes))"
                firms.append(Firm(
                    id: firmID(city: city.id, product: entry.productID, role: .receiver),
                    cityID: city.id,
                    productID: entry.productID,
                    role: .receiver,
                    name: name.trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        return firms
    }

    private static func uniqueIndex<T, ID: Hashable>(
        _ items: [T], id: KeyPath<T, ID>, label: String
    ) throws -> [ID: T] {
        var index: [ID: T] = [:]
        for item in items {
            let key = item[keyPath: id]
            guard index[key] == nil else {
                throw CatalogError.validationFailure("duplicate \(label) id: \(key)")
            }
            index[key] = item
        }
        return index
    }

    private static let maximumCityRoadNodeDistanceKm = 25.0
    /// Gameplay guardrails wide enough for future global normalization while
    /// still catching a missing x1000 fixed-point scale in catalog data.
    private static let plausibleCostIndexRange: ClosedRange<UInt16> = 250...4_000
    private static let plausibleTrafficDelayIndexRange: ClosedRange<UInt16> = 1_000...5_000

    private static func validateNetworkNodes(
        _ nodes: [NetworkNodeDefinition],
        citiesByID: [CityID: CityDefinition],
        networkNodesByID: [RoadNodeID: NetworkNodeDefinition]
    ) throws {
        var linkedCityIDs: Set<CityID> = []
        for node in nodes {
            try validateCoordinate(node.coordinate, label: "road node \(node.id)")
            switch (node.kind, node.cityID) {
            case (.city, .some(let cityID)):
                guard let city = citiesByID[cityID], city.roadNodeID == node.id else {
                    throw CatalogError.validationFailure("road node \(node.id) has invalid city link")
                }
                guard linkedCityIDs.insert(cityID).inserted else {
                    throw CatalogError.validationFailure("city \(cityID) is linked to multiple road nodes")
                }
            case (.junction, .none):
                break
            default:
                throw CatalogError.validationFailure("road node \(node.id) has invalid kind or city link")
            }
        }

        for city in citiesByID.values {
            try validateCoordinate(city.coordinate, label: "city \(city.id)")
            guard let node = networkNodesByID[city.roadNodeID], node.cityID == city.id else {
                throw CatalogError.validationFailure("city \(city.id) references invalid road node")
            }
            guard geographicDistanceKm(city.coordinate, node.coordinate) <= maximumCityRoadNodeDistanceKm else {
                throw CatalogError.validationFailure("city \(city.id) road node is too far from its coordinate")
            }
        }
    }

    private static func validateCoordinate(_ coordinate: GeoCoordinate, label: String) throws {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else {
            throw CatalogError.validationFailure("\(label) has invalid coordinate")
        }
    }

    private static func geographicDistanceKm(_ lhs: GeoCoordinate, _ rhs: GeoCoordinate) -> Double {
        let degreesToRadians = Double.pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * degreesToRadians
        let longitudeDelta = (rhs.longitude - lhs.longitude) * degreesToRadians
        let lhsLatitude = lhs.latitude * degreesToRadians
        let rhsLatitude = rhs.latitude * degreesToRadians
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(lhsLatitude) * cos(rhsLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371 * 2 * asin(sqrt(max(0, min(1, a))))
    }

    private func validate() throws {
        guard !cities.isEmpty else { throw CatalogError.validationFailure("no cities defined") }
        guard !starterCities.isEmpty else { throw CatalogError.validationFailure("no starter city defined") }
        guard !vehicleTypes.isEmpty else { throw CatalogError.validationFailure("no vehicle types defined") }
        guard !products.isEmpty else { throw CatalogError.validationFailure("no products defined") }

        for city in cities {
            guard !city.name.isEmpty, !city.country.isEmpty, city.population > 0,
                  Self.plausibleCostIndexRange.contains(city.costIndex),
                  Self.plausibleTrafficDelayIndexRange.contains(city.trafficDelayIndex) else {
                throw CatalogError.validationFailure("city \(city.id) has invalid baseline data")
            }
        }

        for vehicleType in vehicleTypes {
            guard vehicleType.capacity.massKg > 0, vehicleType.capacity.volumeM3 > 0,
                  vehicleType.speedKmh > 0, vehicleType.purchasePrice > 0,
                  vehicleType.fixedCostPerDay >= 0,
                  vehicleType.costPerKm >= 0, vehicleType.driverCostPerHour >= 0 else {
                throw CatalogError.validationFailure("vehicle type \(vehicleType.id) has non-positive physical values")
            }
        }
        for product in products {
            let massStepKg = ProductDefinition.shipmentMassStepKg
            let minimumMassUnits = product.minimumShipmentMassKg / massStepKg
                + (product.minimumShipmentMassKg % massStepKg == 0 ? 0 : 1)
            let maximumMassUnits = product.maximumShipmentMassKg
                / massStepKg
            guard Self.isStableCatalogID(product.id.rawValue),
                  !product.name.isEmpty, !product.symbol.isEmpty,
                  product.minimumShipmentMassKg > 0,
                  product.maximumShipmentMassKg >= product.minimumShipmentMassKg,
                  minimumMassUnits <= maximumMassUnits,
                  product.densityM3PerTon.isFinite, product.densityM3PerTon > 0 else {
                throw CatalogError.validationFailure("product \(product.id) has invalid ID or physical values")
            }
        }
        try validateCityMarkets()
        guard economy.startingCash > 0, economy.offerGenerationIntervalMinutes > 0,
              economy.offerLifetimeMinutes > 0, economy.loadingMinutes >= 0, economy.unloadingMinutes >= 0,
              (0...100).contains(economy.offerChancePercent), economy.maxOpenOffersPerCity > 0,
              economy.offerSlotPopulation > 0,
              (0...1).contains(economy.fillFloor),
              !economy.urgencyTiers.isEmpty,
              economy.urgencyTiers.allSatisfy({
                  $0.multiplier > 0 && $0.lifetimeMinutes > 0 && $0.weight > 0 && !$0.id.isEmpty
              }),
              economy.contractOfferIntervalMinutes > 0,
              economy.maxOpenContractOffers > 0,
              economy.contractDurationDays > 0,
              (0...100).contains(economy.contractMarginPercent),
              (0...100).contains(economy.contractPenaltyPercent) else {
            throw CatalogError.validationFailure("economy config has invalid values")
        }
        guard let cheapestVehicle = vehicleTypes.map(\.purchasePrice).min() else {
            throw CatalogError.validationFailure("no vehicle type is affordable with starting cash")
        }
        for city in starterCities {
            let foundingCost = CityInsight.foundingCost(for: city)
            guard economy.startingCash > foundingCost else {
                throw CatalogError.validationFailure(
                    "starter city \(city.id) founding cost exceeds starting cash"
                )
            }
            guard economy.startingCash - foundingCost >= cheapestVehicle else {
                throw CatalogError.validationFailure(
                    "starter city \(city.id) leaves too little cash for an entry vehicle"
                )
            }
        }

        // The road graph is one component per landmass, not one component
        // overall: America genuinely has no road to Eurasia, and pretending
        // otherwise would let a truck drive the Atlantic. What must hold is
        // that no node is stranded — every component has to carry at least one
        // city, or a road ends somewhere the simulation can never reach.
        guard !networkNodes.isEmpty else {
            throw CatalogError.validationFailure("no road nodes defined")
        }
        let cityNodeIDs = Set(cities.map(\.roadNodeID))
        var unvisited = Set(networkNodes.map(\.id))
        while let seed = unvisited.first {
            var component: Set<RoadNodeID> = [seed]
            var pending: [RoadNodeID] = [seed]
            while let node = pending.popLast() {
                for edge in adjacency[node] ?? [] where component.insert(edge.neighbor).inserted {
                    pending.append(edge.neighbor)
                }
            }
            guard !component.isDisjoint(with: cityNodeIDs) else {
                throw CatalogError.validationFailure(
                    "road network has a \(component.count)-node island with no city on it"
                )
            }
            unvisited.subtract(component)
        }
    }

    private func validateCityMarkets() throws {
        let cityIDs = Set(cities.map(\.id))
        let marketCityIDs = Set(cityMarkets.map(\.cityID))
        guard marketCityIDs == cityIDs else {
            throw CatalogError.validationFailure("city market profiles do not match the city catalog")
        }

        for market in cityMarkets {
            try validateMarketEntries(market.supply, cityID: market.cityID, label: "supply")
            try validateMarketEntries(market.demand, cityID: market.cityID, label: "demand")
        }
    }

    private func validateMarketEntries(
        _ entries: [CityProductWeight],
        cityID: CityID,
        label: String
    ) throws {
        guard entries.count <= 20 else {
            throw CatalogError.validationFailure("city \(cityID) has more than 20 \(label) products")
        }

        var seen: Set<ProductID> = []
        for entry in entries {
            guard productsByID[entry.productID] != nil else {
                throw CatalogError.validationFailure(
                    "city \(cityID) \(label) references unknown product \(entry.productID)"
                )
            }
            guard entry.weight > 0, seen.insert(entry.productID).inserted else {
                throw CatalogError.validationFailure(
                    "city \(cityID) \(label) has zero weight or a duplicate product"
                )
            }
        }

        let canonical = entries.sorted {
            $0.weight == $1.weight
                ? $0.productID.rawValue < $1.productID.rawValue
                : $0.weight > $1.weight
        }
        guard entries == canonical else {
            throw CatalogError.validationFailure(
                "city \(cityID) \(label) products are not in canonical order"
            )
        }
    }

    private static func isStableCatalogID(_ value: String) -> Bool {
        value.range(
            of: "^[a-z0-9]+(?:_[a-z0-9]+)*$",
            options: .regularExpression
        ) != nil
    }
}
