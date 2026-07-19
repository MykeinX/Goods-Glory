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
    private let junction = RoadNodeID("junction_one")
    private let roadAJ = RoadID("alpha_junction")
    private let roadJB = RoadID("junction_beta")
    private let roadBC = RoadID("beta_gamma")

    @Test func bundledCatalogLoadsAndValidates() throws {
        let catalog = try GameCatalog.load(from: .main)
        #expect(!catalog.cities.isEmpty)
        #expect(!catalog.networkNodes.isEmpty)
        #expect(!catalog.starterCities.isEmpty)
        #expect(!catalog.vehicleTypes.isEmpty)
        #expect(!catalog.products.isEmpty)
        #expect(catalog.cityMarkets.count == catalog.cities.count)
        #expect(catalog.cities.count == 22)
        #expect(catalog.networkNodes.count >= 500)
        #expect(catalog.roads.count >= 700)
        #expect(catalog.cities.allSatisfy { $0.id.rawValue.hasPrefix("us_") })
        #expect(catalog.product(ProductID("consumer_electronics")) != nil)
        for city in catalog.cities {
            #expect(city.population > 0)
            #expect((250...4_000).contains(city.costIndex))
            #expect((1_000...5_000).contains(city.trafficDelayIndex))
            #expect(catalog.cityMarket(city.id) != nil)
        }
        #expect(catalog.cities.contains { $0.hasSeaPortAccess })
        #expect(catalog.cities.contains { !$0.hasAirCargoAccess })
        #expect(catalog.cities.contains { !$0.hasRailFreightAccess })
        #expect(catalog.city(CityID("us_las_vegas"))?.hasRailFreightAccess == false)
        #expect(catalog.city(CityID("us_new_orleans"))?.hasSeaPortAccess == true)
        #expect(catalog.city(CityID("us_st_louis"))?.hasAirCargoAccess == false)
        #expect(catalog.city(CityID("us_dallas"))?.hasSeaPortAccess == false)
        #expect(catalog.starterCities.count >= 6)
        #expect(catalog.cities.contains { $0.isStarterCity && $0.id == CityID("us_seattle") })
        #expect(catalog.cities.contains { $0.isStarterCity && $0.id == CityID("us_miami") })
        #expect(catalog.cities.contains { $0.isStarterCity && $0.id == CityID("us_los_angeles") })
        #expect(catalog.city(CityID("us_st_louis"))?.isStarterCity == false)
        #expect(catalog.city(CityID("us_dallas"))?.isStarterCity == false)
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

    @Test func bundledCatalogProvidesNationwideRoutes() throws {
        let catalog = try GameCatalog.load(from: .main)
        let pairs = [
            (CityID("us_los_angeles"), CityID("us_new_york"), 3_500.0...5_200.0),
            (CityID("us_seattle"), CityID("us_miami"), 4_500.0...6_200.0),
            (CityID("us_denver"), CityID("us_salt_lake_city"), 450.0...900.0)
        ]

        for (origin, destination, plausibleDistance) in pairs {
            let route = try #require(catalog.shortestRoute(from: origin, to: destination))
            #expect(plausibleDistance.contains(route.distanceKm))
            #expect(!route.traversals.isEmpty)
            #expect(route.nodes.first == catalog.city(origin)?.roadNodeID)
            #expect(route.nodes.last == catalog.city(destination)?.roadNodeID)
        }
    }

    @Test func allCitiesAreConnected() throws {
        let catalog = try GameCatalog.load(from: .main)
        for origin in catalog.cities {
            #expect(catalog.reachableCities(from: origin.id).count == catalog.cities.count - 1)
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
        #expect(forward.nodes == [nodeA, junction, nodeB, nodeC])
        #expect(forward.traversals == [
            RoadTraversal(roadID: roadAJ, direction: .forward),
            RoadTraversal(roadID: roadJB, direction: .forward),
            RoadTraversal(roadID: roadBC, direction: .forward)
        ])

        let reverse = try #require(catalog.shortestRoute(from: cityC, to: cityA))
        #expect(reverse.cities == [cityC, cityB, cityA])
        #expect(reverse.nodes == [nodeC, nodeB, junction, nodeA])
        #expect(reverse.traversals == [
            RoadTraversal(roadID: roadBC, direction: .reverse),
            RoadTraversal(roadID: roadJB, direction: .reverse),
            RoadTraversal(roadID: roadAJ, direction: .reverse)
        ])
    }

    @Test func shortestRouteBreaksEqualCostTiesByNodeID() throws {
        let roadJC = RoadID("junction_gamma")
        let catalog = try graphCatalog(roads: [
            validRoadAJ,
            makeRoad(id: roadJC, from: junction, to: nodeC),
            makeRoad(id: RoadID("alpha_beta"), from: nodeA, to: nodeB),
            validRoadBC
        ])

        let route = try #require(catalog.shortestRoute(from: cityA, to: cityC))
        #expect(route.nodes == [nodeA, junction, nodeC])
        #expect(route.cities == [cityA, cityC])
        #expect(route.traversals == [
            RoadTraversal(roadID: roadAJ, direction: .forward),
            RoadTraversal(roadID: roadJC, direction: .forward)
        ])
        #expect(route.distanceKm == 200)
    }

    @Test func duplicateRoadIDsAreRejected() throws {
        let duplicate = makeRoad(
            id: roadAJ,
            from: junction,
            to: nodeB
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(roads: [validRoadAJ, duplicate])
        }
    }

    @Test func disconnectedRoadComponentIsRejected() throws {
        let isolatedA = RoadNodeID("isolated_a")
        let isolatedB = RoadNodeID("isolated_b")
        let isolatedAPoint = GeoCoordinate(latitude: 1, longitude: 0)
        let isolatedBPoint = GeoCoordinate(latitude: 1, longitude: 1)
        let nodes = validNetworkNodes + [
            NetworkNodeDefinition(id: isolatedA, coordinate: isolatedAPoint, kind: .junction, cityID: nil),
            NetworkNodeDefinition(id: isolatedB, coordinate: isolatedBPoint, kind: .junction, cityID: nil)
        ]
        let roads = [validRoadAJ, validRoadJB, validRoadBC, makeRoad(
            id: RoadID("isolated_road"),
            from: isolatedA,
            to: isolatedB
        )]

        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(roads: roads, networkNodes: nodes)
        }
    }

    /// The world is not one road network and must not be forced into one.
    /// America has no road to Eurasia, so the catalog carries two components on
    /// purpose; only a component with no city on it is a real defect.
    @Test func separateRoadNetworksAreAllowedWhenEachCarriesACity() throws {
        // Drop the road joining Beta to Gamma: Gamma keeps its own node and is
        // reachable by nothing, exactly like a second continent.
        let catalog = try graphCatalog(roads: [validRoadAJ, validRoadJB])

        #expect(catalog.shortestRoute(from: cityA, to: cityB) != nil)
        #expect(catalog.shortestRoute(from: cityA, to: cityC) == nil)
        #expect(catalog.roadDistanceKm(from: cityA, to: cityC) == nil)
        // Reachability must reflect the graph, not the city list.
        #expect(!catalog.reachableCities(from: cityA).contains(cityC))
        #expect(catalog.reachableCities(from: cityA).contains(cityB))
    }

    @Test func nonPositiveRoadDistanceIsRejected() throws {
        let road = RoadDefinition(
            id: roadAJ,
            from: nodeA,
            to: junction,
            distanceKm: 0
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(roads: [road, validRoadJB, validRoadBC])
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
            id: roadAJ,
            from: nodeA,
            to: junction
        )

        let catalog = try graphCatalog(
            roads: [accessRoad, validRoadJB, validRoadBC],
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
        nodes[3] = NetworkNodeDefinition(
            id: junction,
            coordinate: junctionPoint,
            kind: .junction,
            cityID: cityA
        )
        #expect(throws: GameCatalog.CatalogError.self) {
            try graphCatalog(networkNodes: nodes)
        }
    }

    private var cityAPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 0) }
    private var cityBPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 1) }
    private var cityCPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 2) }
    private var junctionPoint: GeoCoordinate { GeoCoordinate(latitude: 0, longitude: 0.5) }

    private var validRoadAJ: RoadDefinition {
        makeRoad(id: roadAJ, from: nodeA, to: junction)
    }

    private var validRoadJB: RoadDefinition {
        makeRoad(id: roadJB, from: junction, to: nodeB)
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
            NetworkNodeDefinition(id: nodeC, coordinate: cityCPoint, kind: .city, cityID: cityC),
            NetworkNodeDefinition(id: junction, coordinate: junctionPoint, kind: .junction, cityID: nil)
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
            roads: roads ?? [validRoadAJ, validRoadJB, validRoadBC],
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
