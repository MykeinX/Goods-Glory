//
//  MapFoundationTests.swift
//  Goods&GloryTests
//
//  Verifies the contract between canonical road geometry and map rendering.
//

import Foundation
import Testing
@testable import Goods_Glory

struct MapFoundationTests {
    @MainActor @Test func geographyDecodesLandMasses() throws {
        let data = Data(
            """
            {
              "version": 1,
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
              ],
              "waterBodies": [],
              "rivers": [],
              "boundaries": []
            }
            """.utf8
        )

        let geography = try JSONDecoder().decode(MapGeographyDefinition.self, from: data)

        #expect(geography.landMasses.map(\.id) == ["mainland"])
        #expect(geography.allCoordinates.count == 3)
    }

    @Test func bundledGeographyLoads() throws {
        let geography = try MapGeographyDefinition.load(from: .main)
        #expect(geography.version > 0)
        #expect(!geography.landMasses.isEmpty)
        #expect(!geography.waterBodies.isEmpty)
        #expect(!geography.boundaries.isEmpty)
        #expect(geography.boundaries.allSatisfy { $0.points.count >= 2 })

        let latitudes = geography.landMasses.flatMap(\.points).map(\.latitude)
        let longitudes = geography.landMasses.flatMap(\.points).map(\.longitude)
        #expect((latitudes.min() ?? 0) < -30)
        #expect((latitudes.max() ?? 0) > 60)
        #expect((longitudes.min() ?? 0) < -100)
        #expect((longitudes.max() ?? 0) > 100)
    }

    @Test func movingVehicleIsSampledOnRoadGeometryRatherThanCityChord() throws {
        let cityA = CityID("alpha")
        let cityB = CityID("beta")
        let nodeA = RoadNodeID("node_alpha")
        let nodeB = RoadNodeID("node_beta")
        let roadID = RoadID("alpha_beta")
        let vehicleID = VehicleID(rawValue: 1)
        let jobID = JobID(rawValue: 2)
        let vehicleTypeID = VehicleTypeID("van")
        let productID = ProductID("cargo")
        let economy = EconomyConfig(
            startingCash: 10_000,
            loadingMinutes: 0,
            unloadingMinutes: 0,
            offerGenerationIntervalMinutes: 60,
            offerLifetimeMinutes: 60,
            offerChancePercent: 0,
            maxOpenOffersPerCity: 1,
            offerMinimumProfit: 1,
            offerProfitMarginPercent: 20
        )
        let catalog = try GameCatalog(
            cities: [
                CityDefinition(
                    id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST",
                    latitude: 0, longitude: 0, population: 1,
                    hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                    costIndex: 1_000, trafficDelayIndex: 1_000,
                    isStarterCity: true
                ),
                CityDefinition(
                    id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST",
                    latitude: 1, longitude: 1, population: 1,
                    hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                    costIndex: 1_000, trafficDelayIndex: 1_000,
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
                    distanceKm: 200,
                    geometry: [
                        GeoCoordinate(latitude: 0, longitude: 0),
                        GeoCoordinate(latitude: 0, longitude: 1),
                        GeoCoordinate(latitude: 1, longitude: 1)
                    ]
                )
            ],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: vehicleTypeID, name: "Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 1, volumeM3: 1),
                    speedKmh: 100, purchasePrice: 1,
                    costPerKm: 1, driverCostPerHour: 1
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

        let offer = JobOffer(
            id: jobID,
            origin: cityA,
            destination: cityB,
            productID: productID,
            load: LoadSize(massKg: 1, volumeM3: 1),
            payout: 1,
            distanceKm: 200,
            createdAt: .start,
            expiresAt: .start + 500
        )
        let job = ActiveJob(
            id: jobID,
            offer: offer,
            vehicleID: vehicleID,
            deadheadRoute: [],
            deadheadKm: 0,
            route: [RoadTraversal(roadID: roadID, direction: .forward)],
            startedAt: .start,
            phase: .enRoute,
            phaseStartedAt: .start,
            phaseEndsAt: .start + 100
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
                assignedJobID: jobID,
                odometerKm: 0
            )
        ]
        state.activeJobs = [job]

        let projection = MapProjection()
        let marker = try #require(
            MapSceneAdapter.snapshot(state: state, catalog: catalog, projection: projection)
                .vehicles.first
        )
        let roadCorner = projection.point(latitude: 0, longitude: 1)
        let cityChordMidpoint = projection.point(latitude: 0.5, longitude: 0.5)
        #expect(hypot(marker.position.x - roadCorner.x, marker.position.y - roadCorner.y) < 1)
        #expect(hypot(marker.position.x - cityChordMidpoint.x, marker.position.y - cityChordMidpoint.y) > 50)
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

    @Test func pathSimplifierReducesBundledRoadDisplayBudget() throws {
        let catalog = try GameCatalog.load(from: .main)
        let projection = MapProjection()
        var raw = 0
        var simplified = 0
        for road in catalog.roads {
            let points = road.geometry.map(projection.point(for:))
            raw += points.count
            simplified += MapPathSimplifier.simplify(points).count
        }
        #expect(raw > 5_000)
        #expect(simplified < raw / 2)
        #expect(simplified > 500)
    }
}
