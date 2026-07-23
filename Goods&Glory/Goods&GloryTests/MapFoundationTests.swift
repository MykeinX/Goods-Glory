//
//  MapFoundationTests.swift
//  Goods&GloryTests
//
//  Verifies map atlas decoding and city-to-city arc rendering.
//

import CoreGraphics
import Foundation
import Testing
@testable import Goods_Glory

struct MapFoundationTests {
    @Test func boardSilhouetteDecodesLandMasses() throws {
        let data = Data(
            """
            {
              "version": 2,
              "source": "test",
              "landMasses": [
                {
                  "id": "mainland",
                  "points": [
                    { "latitude": 1, "longitude": 2 },
                    { "latitude": 3, "longitude": 4 },
                    { "latitude": 5, "longitude": 6 }
                  ]
                }
              ]
            }
            """.utf8
        )

        let board = try JSONDecoder().decode(MapBoardSilhouette.self, from: data)

        #expect(board.landMasses.map(\.id) == ["mainland"])
        #expect(board.landMasses.flatMap(\.points).count == 3)
    }

    @Test func bundledMapAtlasesLoad() throws {
        let board = try MapBoardSilhouette.load(from: .main)
        let boundaries = try MapBoundaryAtlas.load(from: .main)
        #expect(board.version > 0)
        #expect(boundaries.version > 0)
        #expect(!board.landMasses.isEmpty)
        #expect(!boundaries.lines.isEmpty)
        #expect(boundaries.lines.allSatisfy { $0.count >= 2 })

        let latitudes = board.landMasses.flatMap(\.points).map(\.latitude)
        let longitudes = board.landMasses.flatMap(\.points).map(\.longitude)
        #expect((latitudes.min() ?? 0) < -30)
        #expect((latitudes.max() ?? 0) > 60)
        #expect((longitudes.min() ?? 0) < -100)
        #expect((longitudes.max() ?? 0) > 100)
    }

    @MainActor @Test func movingVehicleRidesItsDrawnCorridorAtHalfProgress() throws {
        let cityA = CityID("alpha")
        let cityB = CityID("beta")
        let nodeA = RoadNodeID("node_alpha")
        let nodeB = RoadNodeID("node_beta")
        let roadID = RoadID("alpha_beta")
        let vehicleID = VehicleID(rawValue: 1)
        let routeID = RouteID(rawValue: 2)
        let vehicleTypeID = VehicleTypeID("van")
        let productID = ProductID("cargo")
        let economy = TestEconomy.make(
            startingCash: 15_000,
            loadingMinutes: 0,
            unloadingMinutes: 0
        )
        let catalog = try GameCatalog(
            cities: [
                CityDefinition(
                    id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST",
                    latitude: 0, longitude: 0, population: 1,
                    hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000,
                    isStarterCity: true
                ),
                CityDefinition(
                    id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST",
                    latitude: 1, longitude: 1, population: 1,
                    hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000,
                    isStarterCity: false
                )
            ],
            networkNodes: [
                NetworkNodeDefinition(
                    id: nodeA,
                    coordinate: GeoCoordinate(latitude: 0, longitude: 0),
                    kind: .city,
                    cityID: cityA
                ),
                NetworkNodeDefinition(
                    id: nodeB,
                    coordinate: GeoCoordinate(latitude: 1, longitude: 1),
                    kind: .city,
                    cityID: cityB
                )
            ],
            roads: [
                RoadDefinition(
                    id: roadID,
                    from: nodeA,
                    to: nodeB,
                    distanceKm: 200
                )
            ],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: vehicleTypeID, name: "Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 1, volumeM3: 1),
                    speedKmh: 100, purchasePrice: 1,
                    costPerKm: 1, driverCostPerHour: 1,
                    fixedCostPerDay: 10
                )
            ],
            products: [
                ProductDefinition(
                    id: productID, name: "Cargo", symbol: "shippingbox",
                    densityM3PerTon: 1,
                    minimumShipmentMassKg: 50, maximumShipmentMassKg: 50
                )
            ],
            cityMarkets: [
                CityMarketProfile(cityID: cityA, supply: [], demand: []),
                CityMarketProfile(cityID: cityB, supply: [], demand: [])
            ],
            economy: economy
        )

        var state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 1,
                identity: CompanyIdentity(name: "Test", colorHex: "#FFFFFF", emblemSymbol: "star"),
                hqCity: cityA
            ),
            economy: economy
        )
        state.clock = .start + 50
        state.vehicles = [
            Vehicle(
                id: vehicleID,
                typeID: vehicleTypeID,
                cityID: cityA,
                odometerKm: 0
            )
        ]
        state.routes = [
            Route(
                id: routeID,
                name: "Alpha → Beta",
                stops: [RouteStop(id: 1, cityID: cityB, task: .travel)],
                vehicleIDs: [vehicleID],
                isRunning: true
            )
        ]
        state.routeRuns = [
            RouteRun(
                id: 1,
                routeID: routeID,
                vehicleID: vehicleID,
                stopIndex: 0,
                phase: .traveling,
                phaseStartedAt: .start,
                phaseEndsAt: .start + 100,
                legOriginCityID: cityA,
                legDistanceKm: 200,
                lapStartedAt: .start,
                claimedShipmentIDs: [],
                isWindingDown: false
            )
        ]

        let projection = MapProjection()
        let corridors = MapCorridorCache()
        let marker = try #require(
            MapSceneAdapter.snapshot(
                state: state,
                catalog: catalog,
                projection: projection,
                corridors: corridors
            )
            .vehicles.first
        )
        // The vehicle rides the same corridor the map draws, so the expected
        // position is that corridor's midpoint by arc length — not a bezier
        // reconstructed independently, which is exactly the divergence that
        // used to put trucks beside their own route line.
        let corridor = corridors.corridor(
            from: cityA,
            to: cityB,
            catalog: catalog,
            projection: projection
        )
        let expected = corridor.position(at: 0.5)
        #expect(hypot(marker.position.x - expected.x, marker.position.y - expected.y) < 1)
        // Halfway through the leg means halfway along the drawn line.
        let start = corridor.points.first ?? .zero
        let end = corridor.points.last ?? .zero
        #expect(hypot(expected.x - start.x, expected.y - start.y) > 0)
        #expect(hypot(expected.x - end.x, expected.y - end.y) > 0)
    }

    @MainActor @Test func overlappingVehiclesOnCorridorStackTheirLabels() throws {
        let cityA = CityID("alpha")
        let cityB = CityID("beta")
        let nodeA = RoadNodeID("node_alpha")
        let nodeB = RoadNodeID("node_beta")
        let roadID = RoadID("alpha_beta")
        let vehicleTypeID = VehicleTypeID("van")
        let productID = ProductID("cargo")
        let economy = TestEconomy.make(
            startingCash: 15_000,
            loadingMinutes: 0,
            unloadingMinutes: 0
        )
        let catalog = try GameCatalog(
            cities: [
                CityDefinition(
                    id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST",
                    latitude: 0, longitude: 0, population: 1,
                    hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000,
                    isStarterCity: true
                ),
                CityDefinition(
                    id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST",
                    latitude: 1, longitude: 1, population: 1,
                    hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000,
                    isStarterCity: false
                )
            ],
            networkNodes: [
                NetworkNodeDefinition(
                    id: nodeA,
                    coordinate: GeoCoordinate(latitude: 0, longitude: 0),
                    kind: .city,
                    cityID: cityA
                ),
                NetworkNodeDefinition(
                    id: nodeB,
                    coordinate: GeoCoordinate(latitude: 1, longitude: 1),
                    kind: .city,
                    cityID: cityB
                )
            ],
            roads: [
                RoadDefinition(
                    id: roadID,
                    from: nodeA,
                    to: nodeB,
                    distanceKm: 200
                )
            ],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: vehicleTypeID, name: "Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 1, volumeM3: 1),
                    speedKmh: 100, purchasePrice: 1,
                    costPerKm: 1, driverCostPerHour: 1,
                    fixedCostPerDay: 10
                )
            ],
            products: [
                ProductDefinition(
                    id: productID, name: "Cargo", symbol: "shippingbox",
                    densityM3PerTon: 1,
                    minimumShipmentMassKg: 50, maximumShipmentMassKg: 50
                )
            ],
            cityMarkets: [
                CityMarketProfile(cityID: cityA, supply: [], demand: []),
                CityMarketProfile(cityID: cityB, supply: [], demand: [])
            ],
            economy: economy
        )

        var state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 1,
                identity: CompanyIdentity(name: "Test", colorHex: "#FFFFFF", emblemSymbol: "star"),
                hqCity: cityA
            ),
            economy: economy
        )
        // Same corridor progress → same map pixel → labels must stack.
        state.clock = .start + 50
        state.vehicles = [
            Vehicle(
                id: VehicleID(rawValue: 1),
                typeID: vehicleTypeID,
                cityID: cityA,
                odometerKm: 0
            ),
            Vehicle(
                id: VehicleID(rawValue: 2),
                typeID: vehicleTypeID,
                cityID: cityA,
                odometerKm: 0
            )
        ]
        let routeID = RouteID(rawValue: 10)
        state.routes = [
            Route(
                id: routeID,
                name: "Alpha → Beta",
                stops: [RouteStop(id: 1, cityID: cityB, task: .travel)],
                vehicleIDs: state.vehicles.map(\.id),
                isRunning: true
            )
        ]
        state.routeRuns = state.vehicles.enumerated().map { index, vehicle in
            RouteRun(
                id: index + 1,
                routeID: routeID,
                vehicleID: vehicle.id,
                stopIndex: 0,
                phase: .traveling,
                phaseStartedAt: .start,
                phaseEndsAt: .start + 100,
                legOriginCityID: cityA,
                legDistanceKm: 200,
                lapStartedAt: .start,
                claimedShipmentIDs: [],
                isWindingDown: false
            )
        }

        let snapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: catalog,
            projection: MapProjection(),
            corridors: MapCorridorCache()
        )
        #expect(snapshot.vehicles.count == 2)
        let dx = snapshot.vehicles[0].position.x - snapshot.vehicles[1].position.x
        let dy = snapshot.vehicles[0].position.y - snapshot.vehicles[1].position.y
        #expect(hypot(dx, dy) < 1)
        // Stacking is camera-aware and applied by the scene; the pure helper
        // must lift labels once plates nest (~18%), not only when coincident.
        let stacks = MapSceneAdapter.VehicleLabelStacking.indices(
            positions: snapshot.vehicles.map { (id: $0.id, position: $0.position) },
            nodeScale: 1
        )
        #expect(Set(stacks.values) == [0, 1])
    }

    @Test func vehicleLabelStackingStartsWhenPlatesNest() {
        let left = VehicleID(rawValue: 1)
        let right = VehicleID(rawValue: 2)
        let width = MapSceneAdapter.VehicleLabelStacking.plateLocalWidth
        let start = MapSceneAdapter.VehicleLabelStacking.overlapStart
        // Just inside the nest threshold on X, clear on Y.
        let separation = width * (1 - start) * 0.95
        let stacks = MapSceneAdapter.VehicleLabelStacking.indices(
            positions: [
                (id: left, position: .zero),
                (id: right, position: CGPoint(x: separation, y: 0))
            ],
            nodeScale: 1
        )
        #expect(Set(stacks.values) == [0, 1])

        // Farther apart than the nest threshold — labels stay flat.
        let clear = MapSceneAdapter.VehicleLabelStacking.indices(
            positions: [
                (id: left, position: .zero),
                (id: right, position: CGPoint(x: width * 1.1, y: 0))
            ],
            nodeScale: 1
        )
        #expect(Set(clear.values) == [0])
    }

    @MainActor @Test func routePreviewClosesTheLoopAndGroupsRepeatedCityMarkers() throws {
        let catalog = try GameCatalog.load(from: .main)
        let cities = try #require(catalog.cities.count >= 3 ? Array(catalog.cities.prefix(3)) : nil)
        let cityA = cities[0].id
        let cityB = cities[1].id
        let cityC = cities[2].id
        let laneID = LaneID("preview")
        let route = Route(
            id: RouteID(rawValue: 92),
            name: "Preview",
            stops: [
                RouteStop(id: 1, cityID: cityA, task: .travel),
                RouteStop(id: 2, cityID: cityB, task: .pickupLane(laneID)),
                RouteStop(id: 3, cityID: cityB, task: .deliverLane(laneID, .destination)),
                RouteStop(id: 4, cityID: cityC, task: .travel),
                RouteStop(id: 5, cityID: cityA, task: .deliverLane(laneID, .destination))
            ],
            vehicleIDs: [],
            isRunning: false
        )
        let state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 1,
                identity: CompanyIdentity(name: "Test", colorHex: "#FFFFFF", emblemSymbol: "star"),
                hqCity: cityA
            ),
            economy: catalog.economy
        )
        let projection = MapProjection()

        let snapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: catalog,
            projection: projection,
            previewRoute: route,
            corridors: MapCorridorCache()
        )
        let planned = try #require(snapshot.routes.first { $0.kind == .planned })
        let markerA = try #require(snapshot.plannedVisits.first { $0.id == cityA })
        let markerB = try #require(snapshot.plannedVisits.first { $0.id == cityB })

        // Three legs (A→B→C→A), each drawn as a road corridor rather than a
        // single point per visit, so the exact count depends on the terrain.
        // What must hold is that the lap is continuous and closes on itself.
        #expect(planned.anchors.count >= 4)
        #expect(planned.anchors.first == planned.anchors.last)
        #expect(snapshot.plannedVisits.count == 3)
        #expect(markerA.stepNumbers == [1, 4])
        #expect(markerA.hasDelivery)
        #expect(!markerA.hasPickup)
        #expect(markerB.stepNumbers == [2])
        #expect(markerB.hasPickup)
        #expect(markerB.hasDelivery)
    }

    @Test func pathSimplifierKeepsEndpointsAndDropsColinearPoints() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0),
            CGPoint(x: 30, y: 0)
        ]
        let simplified = MapPathSimplifier.simplify(points, tolerance: 4)
        #expect(simplified.first == points.first)
        #expect(simplified.last == points.last)
        #expect(simplified.count == 2)
    }

    @Test func pathSimplifierKeepsSignificantDetours() {
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 40),
            CGPoint(x: 100, y: 0)
        ]
        let simplified = MapPathSimplifier.simplify(points, tolerance: 4)
        #expect(simplified.count == 3)
        #expect(simplified[1] == points[1])
    }
}
