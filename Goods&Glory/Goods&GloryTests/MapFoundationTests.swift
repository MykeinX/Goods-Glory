//
//  MapFoundationTests.swift
//  Goods&GloryTests
//
//  Verifies map geography decoding and city-to-city arc rendering.
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

    @Test func movingVehicleIsSampledOnCityChordAtHalfProgress() throws {
        let cityA = CityID("alpha")
        let cityB = CityID("beta")
        let nodeA = RoadNodeID("node_alpha")
        let nodeB = RoadNodeID("node_beta")
        let roadID = RoadID("alpha_beta")
        let vehicleID = VehicleID(rawValue: 1)
        let jobID = JobID(rawValue: 2)
        let vehicleTypeID = VehicleTypeID("van")
        let productID = ProductID("cargo")
        let economy = TestEconomy.make(
            startingCash: 15_000,
            loadingMinutes: 0,
            unloadingMinutes: 0,
            offerGenerationIntervalMinutes: 60,
            offerLifetimeMinutes: 60,
            offerChancePercent: 0,
            maxOpenOffersPerCity: 1
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
                    freightRatePerKm: 2.0, fixedCostPerDay: 10
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
            urgency: .normal,
            source: .spot,
            contractID: nil,
            originFirmID: nil,
            destinationFirmID: nil,
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
        // Current map adapter interpolates along the projected city-to-city MapArc.
        let originPt = projection.point(latitude: 0, longitude: 0)
        let destPt = projection.point(latitude: 1, longitude: 1)
        let expected = MapArc.point(originPt, destPt, 0.5)
        #expect(hypot(marker.position.x - expected.x, marker.position.y - expected.y) < 1)
    }

    @Test func routePreviewClosesTheLoopAndGroupsRepeatedCityMarkers() throws {
        let catalog = try GameCatalog.load(from: .main)
        let cities = try #require(catalog.cities.count >= 3 ? Array(catalog.cities.prefix(3)) : nil)
        let cityA = cities[0].id
        let cityB = cities[1].id
        let cityC = cities[2].id
        let contractID = ContractID(rawValue: 91)
        let route = Route(
            id: RouteID(rawValue: 92),
            name: "Preview",
            contractID: nil,
            stops: [
                RouteStop(id: 1, cityID: cityA, task: .travel),
                RouteStop(id: 2, cityID: cityB, task: .pickupContract(contractID)),
                RouteStop(id: 3, cityID: cityB, task: .deliverContract(contractID)),
                RouteStop(id: 4, cityID: cityC, task: .travel),
                RouteStop(id: 5, cityID: cityA, task: .deliverContract(contractID))
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
            previewRoute: route
        )
        let planned = try #require(snapshot.routes.first { $0.kind == .planned })
        let markerA = try #require(snapshot.plannedVisits.first { $0.id == cityA })
        let markerB = try #require(snapshot.plannedVisits.first { $0.id == cityB })

        #expect(planned.anchors.count == 4)
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
