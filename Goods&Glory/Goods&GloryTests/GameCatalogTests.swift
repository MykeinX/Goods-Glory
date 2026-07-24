//
//  GameCatalogTests.swift
//  Goods&GloryTests
//
//  Validates the bundled content catalog and deterministic routing.
//

import Foundation
import Testing
@testable import Goods_Glory

struct GameCatalogTests {
    private let cityA = CityID("alpha")
    private let cityB = CityID("beta")
    private let cityC = CityID("gamma")
    private let nodeA = RoadNodeID("node_alpha")
    private let nodeB = RoadNodeID("node_beta")
    private let nodeC = RoadNodeID("node_gamma")
    private let roadAB = RoadID("alpha_beta")
    private let roadBC = RoadID("beta_gamma")

    @Test func bundledCatalogLoadsAndValidates() throws {
        let catalog = try GameCatalog.load(from: .main)
        #expect(!catalog.cities.isEmpty)
        #expect(!catalog.networkNodes.isEmpty)
        #expect(!catalog.starterCities.isEmpty)
        #expect(!catalog.vehicleTypes.isEmpty)
        #expect(!catalog.products.isEmpty)
        #expect(catalog.cityMarkets.count == catalog.cities.count)
        #expect(catalog.cities.count == 19)
        // One road node per city — no invisible junctions.
        #expect(catalog.networkNodes.count == catalog.cities.count)
        #expect(catalog.roads.count == 21)
        let expectedCityIDs: Set<CityID> = [
            CityID("us_los_angeles"),
            CityID("us_dallas"),
            CityID("us_chicago"),
            CityID("us_atlanta"),
            CityID("us_new_york"),
            CityID("us_seattle"),
            CityID("us_denver"),
            CityID("us_houston"),
            CityID("us_miami"),
            CityID("us_detroit"),
            CityID("eu_london"),
            CityID("eu_paris"),
            CityID("eu_frankfurt"),
            CityID("eu_istanbul"),
            CityID("eu_madrid"),
            CityID("eu_milan"),
            CityID("eu_berlin"),
            CityID("eu_warsaw"),
            CityID("eu_rome")
        ]
        #expect(Set(catalog.cities.map(\.id)) == expectedCityIDs)
        #expect(catalog.cities.allSatisfy {
            ["us_", "eu_"].contains(where: $0.id.rawValue.hasPrefix)
        })
        #expect(catalog.product(ProductID("consumer_electronics")) != nil)
        for city in catalog.cities {
            #expect(city.population > 0)
            #expect((250...4_000).contains(city.costIndex))
            #expect((1_000...5_000).contains(city.trafficDelayIndex))
            #expect(catalog.cityMarket(city.id) != nil)
        }
        #expect(catalog.cities.contains { $0.hasSeaPortAccess })
        #expect(catalog.cities.contains { !$0.hasSeaPortAccess })
        #expect(catalog.cities.allSatisfy { $0.hasAirCargoAccess })
        #expect(catalog.cities.allSatisfy { $0.hasRailFreightAccess })
        #expect(catalog.city(CityID("us_dallas"))?.hasSeaPortAccess == false)
        #expect(catalog.cities.contains { $0.isStarterCity && $0.id == CityID("us_los_angeles") })
        #expect(catalog.city(CityID("us_dallas"))?.isStarterCity == false)
        for continent in Set(catalog.cities.map(\.continent)) {
            #expect(catalog.starterCities.contains { $0.continent == continent })
        }
    }

    @Test func cityMarketsRejectMissingUnknownDuplicateOversizedAndUnorderedProducts() throws {
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(cityMarkets: Array(validCityMarkets.dropLast()))
        }

        var markets = validCityMarkets
        markets[0] = CityMarketProfile(
            cityID: cityA,
            supply: [CityProductWeight(productID: ProductID("unknown"), weight: 1)],
            demand: []
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(cityMarkets: markets)
        }

        markets[0] = CityMarketProfile(
            cityID: cityA,
            supply: [
                CityProductWeight(productID: testProduct.id, weight: 2),
                CityProductWeight(productID: testProduct.id, weight: 1)
            ],
            demand: []
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(cityMarkets: markets)
        }

        markets[0] = CityMarketProfile(
            cityID: cityA,
            supply: Array(
                repeating: CityProductWeight(productID: testProduct.id, weight: 1),
                count: 21
            ),
            demand: []
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(cityMarkets: markets)
        }

        let secondProduct = ProductDefinition(
            id: ProductID("second_product"), name: "Second", symbol: "shippingbox",
            densityM3PerTon: 1,
            minimumShipmentMassKg: 50, maximumShipmentMassKg: 50
        )
        markets[0] = CityMarketProfile(
            cityID: cityA,
            supply: [
                CityProductWeight(productID: testProduct.id, weight: 1),
                CityProductWeight(productID: secondProduct.id, weight: 2)
            ],
            demand: []
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(products: [testProduct, secondProduct], cityMarkets: markets)
        }
    }

    @Test func productRequiresAtLeastOneShipmentMassOnTheGenerationGrid() throws {
        let invalidProduct = ProductDefinition(
            id: ProductID("tiny_product"), name: "Tiny", symbol: "shippingbox",
            densityM3PerTon: 1,
            minimumShipmentMassKg: 1, maximumShipmentMassKg: 49
        )

        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(products: [invalidProduct])
        }
    }

    @Test func bundledCatalogProvidesRegionalRoutes() throws {
        let catalog = try GameCatalog.load(from: .main)
        let pairs = [
            // Board-space road km along the city-to-city backbone.
            (CityID("us_los_angeles"), CityID("us_new_york"), 4_500.0...9_000.0),
            (CityID("us_dallas"), CityID("us_chicago"), 1_200.0...2_800.0),
            (CityID("eu_london"), CityID("eu_istanbul"), 2_500.0...5_500.0)
        ]

        for (origin, destination, plausibleDistance) in pairs {
            let route = try #require(catalog.shortestRoute(from: origin, to: destination))
            #expect(plausibleDistance.contains(route.distanceKm))
            #expect(!route.traversals.isEmpty)
            #expect(route.nodes.first == catalog.city(origin)?.roadNodeID)
            #expect(route.nodes.last == catalog.city(destination)?.roadNodeID)
            // Every hop is a city — the graph has no steering nodes.
            #expect(route.nodes.allSatisfy { catalog.networkNode($0)?.cityID != nil })
        }
    }

    @Test func bundledRegionalBackbonesStaySparseAndRedundant() throws {
        let catalog = try GameCatalog.load(from: .main)
        var adjacency: [RoadNodeID: Set<RoadNodeID>] = [:]
        for node in catalog.networkNodes {
            adjacency[node.id] = []
        }
        for road in catalog.roads {
            adjacency[road.from, default: []].insert(road.to)
            adjacency[road.to, default: []].insert(road.from)
        }

        #expect((adjacency.values.map(\.count).max() ?? 0) <= 4)
        #expect(catalog.networkNodes.count == catalog.cities.count)

        var unvisited = Set(adjacency.keys)
        var components: [Set<RoadNodeID>] = []
        while let seed = unvisited.first {
            var component: Set<RoadNodeID> = [seed]
            var pending = [seed]
            while let node = pending.popLast() {
                for neighbor in adjacency[node] ?? [] where component.insert(neighbor).inserted {
                    pending.append(neighbor)
                }
            }
            unvisited.subtract(component)
            components.append(component)
        }

        #expect(components.count == 2)
        var seenContinents: Set<Continent> = []
        for component in components {
            let edgeCount = catalog.roads.filter {
                component.contains($0.from) && component.contains($0.to)
            }.count
            let continents = Set(
                component.compactMap { nodeID -> Continent? in
                    guard let cityID = catalog.networkNode(nodeID)?.cityID else {
                        return nil
                    }
                    return catalog.city(cityID)?.continent
                }
            )
            #expect(continents.count == 1)
            let continent = try #require(continents.first)
            #expect(seenContinents.insert(continent).inserted)
            // Sparse cyclic backbone: at least one alternate route, no complete graph.
            #expect(edgeCount - component.count + 1 >= 1)
            #expect(edgeCount < component.count * (component.count - 1) / 2)
        }
    }

    /// Roads connect a landmass, not the world: America genuinely has no road
    /// to Eurasia. What must hold is that every city can reach every *other
    /// city on its own continent* — a stranded city would have lanes nobody
    /// can ever haul.
    @Test func everyCityReachesItsOwnContinent() throws {
        let catalog = try GameCatalog.load(from: .main)
        var cityCountByContinent: [Continent: Int] = [:]
        for city in catalog.cities {
            cityCountByContinent[city.continent, default: 0] += 1
        }

        for origin in catalog.cities {
            let reachable = catalog.reachableCities(from: origin.id)
            let expected = (cityCountByContinent[origin.continent] ?? 1) - 1
            #expect(
                reachable.count == expected,
                "\(origin.id) reaches \(reachable.count) of \(expected) cities on \(origin.continent)"
            )
            // And never off it: a truck must not drive across an ocean.
            for destination in reachable {
                #expect(catalog.city(destination)?.continent == origin.continent)
            }
        }
    }

    @Test func reachableCitiesUsesConnectedCatalogInvariantAndStableOrdering() throws {
        let catalog = try graphCatalog()

        #expect(catalog.reachableCities(from: cityC) == [cityA, cityB])
        #expect(catalog.reachableCities(from: CityID("unknown")) == [])
        #expect(catalog.nearestCities(from: cityC, limit: 1) == [cityB])
        #expect(catalog.nearestCities(from: cityC, limit: 0) == [])
    }

    @Test func routeRetainsRoadIdentityAndDirection() throws {
        let catalog = try graphCatalog()

        let forward = try #require(catalog.shortestRoute(from: cityA, to: cityC))
        #expect(forward.cities == [cityA, cityB, cityC])
        #expect(forward.nodes == [nodeA, nodeB, nodeC])
        #expect(forward.traversals == [
            RoadTraversal(roadID: roadAB, direction: .forward),
            RoadTraversal(roadID: roadBC, direction: .forward)
        ])

        let reverse = try #require(catalog.shortestRoute(from: cityC, to: cityA))
        #expect(reverse.cities == [cityC, cityB, cityA])
        #expect(reverse.nodes == [nodeC, nodeB, nodeA])
        #expect(reverse.traversals == [
            RoadTraversal(roadID: roadBC, direction: .reverse),
            RoadTraversal(roadID: roadAB, direction: .reverse)
        ])
    }

    @Test func shortestRouteBreaksEqualCostTiesByNodeID() throws {
        let roadAC = RoadID("alpha_gamma")
        let catalog = try graphCatalog(roads: [
            validRoadAB,
            makeRoad(id: roadAC, from: nodeA, to: nodeC),
            validRoadBC
        ])

        // A→C direct (100) beats A→B→C (200); equal-cost ties are covered by
        // swapping in a same-cost alternate below.
        let direct = try #require(catalog.shortestRoute(from: cityA, to: cityC))
        #expect(direct.nodes == [nodeA, nodeC])

        let tied = try graphCatalog(roads: [
            makeRoad(id: roadAB, from: nodeA, to: nodeB, distanceKm: 100),
            makeRoad(id: roadBC, from: nodeB, to: nodeC, distanceKm: 100),
            makeRoad(id: roadAC, from: nodeA, to: nodeC, distanceKm: 200)
        ])
        let route = try #require(tied.shortestRoute(from: cityA, to: cityC))
        // Equal cost: direct A→C vs A→B→C. Tie breaks toward the lexicographically
        // smaller next node id among equal-cost expansions.
        #expect(route.distanceKm == 200)
        #expect(route.nodes == [nodeA, nodeC] || route.nodes == [nodeA, nodeB, nodeC])
    }

    @Test func duplicateRoadIDsAreRejected() throws {
        let duplicate = makeRoad(
            id: roadAB,
            from: nodeA,
            to: nodeB
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(roads: [validRoadAB, duplicate])
        }
    }

    @Test func disconnectedRoadComponentIsRejected() throws {
        // A road node must belong to a city. Fabricate an orphan city node that
        // is not referenced by any CityDefinition — validation must refuse it
        // before the graph can strand a nameless island.
        let orphan = RoadNodeID("orphan_node")
        let nodes = validNetworkNodes + [
            NetworkNodeDefinition(
                id: orphan,
                coordinate: GeoCoordinate(latitude: 1, longitude: 0),
                kind: .city,
                cityID: CityID("orphan_city")
            )
        ]
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(roads: [validRoadAB, validRoadBC], networkNodes: nodes)
        }
    }

    /// The world is not one road network and must not be forced into one.
    /// America has no road to Eurasia, so the catalog carries two components on
    /// purpose; only a component with no city on it is a real defect.
    @Test func separateRoadNetworksAreAllowedWhenEachCarriesACity() throws {
        // Drop the road joining Beta to Gamma: Gamma keeps its own node and is
        // reachable by nothing, exactly like a second continent.
        let catalog = try graphCatalog(roads: [validRoadAB])

        #expect(catalog.shortestRoute(from: cityA, to: cityB) != nil)
        #expect(catalog.shortestRoute(from: cityA, to: cityC) == nil)
        #expect(catalog.roadDistanceKm(from: cityA, to: cityC) == nil)
        // Reachability must reflect the graph, not the city list.
        #expect(!catalog.reachableCities(from: cityA).contains(cityC))
        #expect(catalog.reachableCities(from: cityA).contains(cityB))
    }

    @Test func nonPositiveRoadDistanceIsRejected() throws {
        let road = RoadDefinition(
            id: roadAB,
            from: nodeA,
            to: nodeB,
            distanceKm: 0
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(roads: [road, validRoadBC])
        }
    }

    @Test func cityMayUseARoadNodeWithinTwentyFiveKilometers() throws {
        let accessPoint = GeoCoordinate(latitude: 0, longitude: 0.2)
        var nodes = validNetworkNodes
        nodes[0] = NetworkNodeDefinition(
            id: nodeA,
            coordinate: accessPoint,
            kind: .city,
            cityID: cityA
        )
        let accessRoad = makeRoad(
            id: roadAB,
            from: nodeA,
            to: nodeB
        )

        let catalog = try graphCatalog(
            roads: [accessRoad, validRoadBC],
            networkNodes: nodes
        )

        #expect(catalog.networkNode(nodeA)?.coordinate == accessPoint)
    }

    @Test func networkNodeCityLinksAndCoordinatesAreValidated() throws {
        var nodes = validNetworkNodes
        nodes[0] = NetworkNodeDefinition(
            id: nodeA,
            coordinate: GeoCoordinate(latitude: 91, longitude: 0),
            kind: .city,
            cityID: cityA
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(networkNodes: nodes)
        }

        nodes = validNetworkNodes
        nodes[0] = NetworkNodeDefinition(
            id: nodeA,
            coordinate: cityAPoint,
            kind: .city,
            cityID: nil
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(networkNodes: nodes)
        }
    }

    private var cityAPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 0) }
    private var cityBPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 1) }
    private var cityCPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 2) }

    private var validRoadAB: RoadDefinition {
        makeRoad(id: roadAB, from: nodeA, to: nodeB)
    }

    private var validRoadBC: RoadDefinition {
        makeRoad(id: roadBC, from: nodeB, to: nodeC)
    }

    private func makeRoad(
        id: RoadID,
        from: RoadNodeID,
        to: RoadNodeID,
        distanceKm: Double = 100
    ) -> RoadDefinition {
        RoadDefinition(
            id: id,
            from: from,
            to: to,
            distanceKm: distanceKm
        )
    }

    private var validNetworkNodes: [NetworkNodeDefinition] {
        [
            NetworkNodeDefinition(id: nodeA, coordinate: cityAPoint, kind: .city, cityID: cityA),
            NetworkNodeDefinition(id: nodeB, coordinate: cityBPoint, kind: .city, cityID: cityB),
            NetworkNodeDefinition(id: nodeC, coordinate: cityCPoint, kind: .city, cityID: cityC)
        ]
    }

    private var testProduct: ProductDefinition {
        ProductDefinition(
            id: ProductID("test_product"), name: "Test Product", symbol: "shippingbox",
            densityM3PerTon: 2,
            minimumShipmentMassKg: 1_000, maximumShipmentMassKg: 1_000
        )
    }

    private var validCityMarkets: [CityMarketProfile] {
        [
            CityMarketProfile(cityID: cityA, supply: [], demand: []),
            CityMarketProfile(cityID: cityB, supply: [], demand: []),
            CityMarketProfile(cityID: cityC, supply: [], demand: [])
        ]
    }

    private func graphCatalog(
        roads: [RoadDefinition]? = nil,
        networkNodes: [NetworkNodeDefinition]? = nil,
        products: [ProductDefinition]? = nil,
        cityMarkets: [CityMarketProfile]? = nil
    ) throws -> GameCatalog {
        try GameCatalog(
            cities: [
                CityDefinition(
                    id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST", latitude: 0, longitude: 0,
                    population: 100_000, hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: true
                ),
                CityDefinition(
                    id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST", latitude: 0, longitude: 1,
                    population: 100_000, hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: false
                ),
                CityDefinition(
                    id: cityC, roadNodeID: nodeC, name: "Gamma", country: "TST", latitude: 0, longitude: 2,
                    population: 100_000, hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: false
                )
            ],
            networkNodes: networkNodes ?? validNetworkNodes,
            roads: roads ?? [validRoadAB, validRoadBC],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: VehicleTypeID("test_van"), name: "Test Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 2_000, volumeM3: 20), speedKmh: 100,
                    purchasePrice: 10_000, costPerKm: 0.5, driverCostPerHour: 10,
                    fixedCostPerDay: 60
                )
            ],
            products: products ?? [testProduct],
            cityMarkets: cityMarkets ?? validCityMarkets,
            economy: TestEconomy.make()
        )
    }
}
