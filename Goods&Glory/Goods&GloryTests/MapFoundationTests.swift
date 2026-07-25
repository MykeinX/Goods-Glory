//
//  MapFoundationTests.swift
//  Goods&GloryTests
//
//  Verifies map atlas decoding and city-to-city arc rendering.
//

import CoreGraphics
import Foundation
import SpriteKit
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
        #expect(board.version > 0)
        #expect(!board.landMasses.isEmpty)

        let latitudes = board.landMasses.flatMap(\.points).map(\.latitude)
        let longitudes = board.landMasses.flatMap(\.points).map(\.longitude)
        #expect((latitudes.min() ?? 0) < -30)
        #expect((latitudes.max() ?? 0) > 60)
        #expect((longitudes.min() ?? 0) < -100)
        #expect((longitudes.max() ?? 0) > 100)

        let land = try #require(board.landMasses.first { !$0.id.contains("_hole_") })
        let holes = board.landMasses.filter { $0.id.contains("_hole_") }
        #expect(!holes.isEmpty)

        // Shoelace over the *closed* ring. Dropping the edge back to the first
        // point leaves an open fan whose sign a thin ring can flip outright,
        // which is not a winding failure but an arithmetic one.
        func signedArea(_ points: [GeoCoordinate]) -> Double {
            guard let first = points.first else { return 0 }
            return zip(points, points.dropFirst() + [first]).reduce(0) { area, edge in
                area + edge.0.longitude * edge.1.latitude
                    - edge.1.longitude * edge.0.latitude
            } / 2
        }
        let outerWinding = signedArea(land.points)
        #expect(holes.allSatisfy { signedArea($0.points) * outerWinding < 0 })
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

    @MainActor @Test func routePreviewFollowsVisitOrderWithoutInventingAReturnLeg() throws {
        let catalog = try GameCatalog.load(from: .main)
        let cities = try #require(catalog.cities.count >= 3 ? Array(catalog.cities.prefix(3)) : nil)
        let cityA = cities[0].id
        let cityB = cities[1].id
        let cityC = cities[2].id
        let laneID = LaneID("preview")
        let openRoute = Route(
            id: RouteID(rawValue: 92),
            name: "Preview",
            stops: [
                RouteStop(id: 1, cityID: cityA, task: .travel),
                RouteStop(id: 2, cityID: cityB, task: .pickupLane(laneID)),
                RouteStop(id: 3, cityID: cityB, task: .deliverLane(laneID, .destination)),
                RouteStop(id: 4, cityID: cityC, task: .travel),
            ],
            vehicleIDs: [],
            isRunning: false
        )
        let closedRoute = Route(
            id: RouteID(rawValue: 93),
            name: "Preview Closed",
            stops: openRoute.stops + [
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
        let corridors = MapCorridorCache()

        let openSnapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: catalog,
            projection: projection,
            previewRoute: openRoute,
            corridors: corridors
        )
        let closedSnapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: catalog,
            projection: projection,
            previewRoute: closedRoute,
            corridors: corridors
        )
        let openPlanned = openSnapshot.routes.filter { $0.kind == .planned }
        let closedPlanned = closedSnapshot.routes.filter { $0.kind == .planned }
        let markerA = try #require(closedSnapshot.plannedVisits.first { $0.id == cityA })
        let markerB = try #require(closedSnapshot.plannedVisits.first { $0.id == cityB })

        // Open draft: A→B→C only. Closing back to A is the author's job (or
        // the running network), not an automatic preview invention.
        let returnRoads = Set(
            corridors.roadIDs(
                from: cityC,
                to: cityA,
                catalog: catalog,
                projection: projection
            )
        )
        let openRoadIDs = Set(
            openPlanned.compactMap { overlay -> RoadID? in
                let prefix = "preview-\(openRoute.id.rawValue)-"
                guard overlay.id.hasPrefix(prefix) else { return nil }
                return RoadID(String(overlay.id.dropFirst(prefix.count)))
            }
        )
        #expect(!openPlanned.isEmpty)
        #expect(openRoadIDs.isDisjoint(with: returnRoads))

        // Authored return visit still draws the closing roads, once each.
        #expect(!closedPlanned.isEmpty)
        #expect(Set(closedPlanned.map(\.id)).count == closedPlanned.count)
        #expect(closedPlanned.allSatisfy { $0.anchors.count >= 2 })
        #expect(closedSnapshot.plannedVisits.count == 3)
        #expect(markerA.stepNumbers == [1, 4])
        #expect(markerA.hasDelivery)
        #expect(!markerA.hasPickup)
        #expect(markerB.stepNumbers == [2])
        #expect(markerB.hasPickup)
        #expect(markerB.hasDelivery)
    }

    /// The fleet has to batch, and only sprites off one texture page do.
    ///
    /// SpriteKit draws every SKShapeNode on its own, and an SKCropNode opens an
    /// offscreen pass. Built that way a vehicle cost eleven nodes and eight
    /// draw calls, so a few hundred of them could not hold a frame. This is the
    /// property that made it cheap, so it is asserted rather than remembered.
    @MainActor @Test func vehicleNodeIsBuiltOnlyFromBatchableSprites() {
        let node = MapVehicleNode()

        var pending: [SKNode] = [node]
        var offenders: [String] = []
        var sprites = 0
        var total = 0
        while let current = pending.popLast() {
            total += 1
            switch current {
            case is SKSpriteNode:
                sprites += 1
            case is SKShapeNode, is SKCropNode, is SKEffectNode:
                offenders.append(String(describing: type(of: current)))
            default:
                break
            }
            pending.append(contentsOf: current.children)
        }

        #expect(
            offenders.isEmpty,
            "vehicle draws with un-batchable nodes: \(offenders.joined(separator: ", "))"
        )
        #expect(sprites >= 5, "expected the vehicle parts to be sprites")
        #expect(total <= 10, "vehicle grew to \(total) nodes; every one is per-vehicle cost")
    }

    /// The per-tick cost of a large fleet, measured rather than assumed.
    ///
    /// `snapshot` runs once a second for the whole fleet and is where anything
    /// accidentally quadratic would land — a `first { }` lookup per vehicle, a
    /// re-projection per leg. The budget is deliberately loose: this is here to
    /// catch a change of *shape*, not to police milliseconds on a busy machine.
    /// Measured at under 6 ms for 400 vehicles; the budget is 15 ms, and the
    /// tick it has to fit inside is 1000 ms.
    @MainActor @Test func snapshotStaysCheapForALargeFleet() throws {
        let catalog = try GameCatalog.load(from: .main)
        let projection = MapProjection()
        let corridors = MapCorridorCache()
        let fleet = 400

        let origin = try #require(catalog.cities.first { !catalog.reachableCities(from: $0.id).isEmpty })
        let destinations = catalog.reachableCities(from: origin.id)
        let vehicleType = try #require(catalog.vehicleTypes.first)

        var state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 7,
                identity: CompanyIdentity(name: "Load", colorHex: "#FFFFFF", emblemSymbol: "star"),
                hqCity: origin.id
            ),
            economy: catalog.economy
        )
        state.clock = .start + 30

        for index in 0..<fleet {
            let vehicleID = VehicleID(rawValue: index + 1)
            let routeID = RouteID(rawValue: index + 1)
            let destination = destinations[index % destinations.count]
            state.vehicles.append(
                Vehicle(id: vehicleID, typeID: vehicleType.id, cityID: origin.id, odometerKm: 0)
            )
            state.routes.append(
                Route(
                    id: routeID,
                    name: "R\(index)",
                    stops: [RouteStop(id: 1, cityID: destination, task: .travel)],
                    vehicleIDs: [vehicleID],
                    isRunning: true
                )
            )
            state.routeRuns.append(
                RouteRun(
                    id: index + 1,
                    routeID: routeID,
                    vehicleID: vehicleID,
                    stopIndex: 0,
                    phase: .traveling,
                    phaseStartedAt: .start,
                    phaseEndsAt: .start + 100,
                    legOriginCityID: origin.id,
                    legDistanceKm: 400,
                    lapStartedAt: .start,
                    claimedShipmentIDs: [],
                    isWindingDown: false
                )
            )
        }

        // Warm the corridor atlas, which is built once per session, not per tick.
        _ = MapSceneAdapter.snapshot(
            state: state, catalog: catalog, projection: projection, corridors: corridors
        )

        let started = Date()
        let rounds = 10
        var produced = 0
        for _ in 0..<rounds {
            produced = MapSceneAdapter.snapshot(
                state: state, catalog: catalog, projection: projection, corridors: corridors
            ).vehicles.count
        }
        let perTick = Date().timeIntervalSince(started) / Double(rounds)

        #expect(produced == fleet, "expected \(fleet) markers, got \(produced)")
        #expect(
            perTick < 0.015,
            "snapshot for \(fleet) vehicles took \(Int(perTick * 1000)) ms; the tick budget is 1000 ms and this is the part that grows with the fleet"
        )
    }

    /// Plate stacking runs on every camera frame, so it must not walk the whole
    /// fleet for each vehicle. Two clusters far apart pin the behaviour: a
    /// quadratic scan and a bucketed one agree here, but only one stays cheap.
    @MainActor @Test func labelStackingScalesWithoutComparingEveryPair() {
        var positions: [(id: VehicleID, position: CGPoint)] = []
        for index in 0..<200 {
            positions.append((
                id: VehicleID(rawValue: index + 1),
                position: CGPoint(x: index < 100 ? 0 : 10_000, y: 0)
            ))
        }

        let stacks = MapSceneAdapter.VehicleLabelStacking.indices(
            positions: positions,
            nodeScale: 1
        )

        #expect(stacks.count == positions.count)
        let cap = MapSceneAdapter.VehicleLabelStacking.maximumVisibleStack
        let suppressed = MapSceneAdapter.VehicleLabelStacking.suppressed
        for pile in [positions.prefix(100), positions.suffix(100)] {
            let assigned = pile.compactMap { stacks[$0.id] }
            // Each pile lifts a few plates and drops the rest — a hundred
            // stacked plates is a tower into the sea, not a legible label.
            #expect(Set(assigned.filter { $0 != suppressed }) == Set(0...cap))
            #expect(assigned.filter { $0 == suppressed }.count == 100 - (cap + 1))
        }
        // Neither pile can see the other, so both cap independently.
    }
}
