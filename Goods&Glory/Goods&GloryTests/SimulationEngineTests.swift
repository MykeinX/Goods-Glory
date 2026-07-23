//
//  SimulationEngineTests.swift
//  Goods&GloryTests
//
//  Engine rules and the determinism contract, exercised on a small
//  code-defined fixture catalog (independent of bundled content).
//

import Foundation
import Testing
@testable import Goods_Glory

// MARK: - Fixture

private enum Fixture {
    static let cityA = CityID("alpha")
    static let cityB = CityID("beta")
    static let nodeA = RoadNodeID("node_alpha")
    static let nodeB = RoadNodeID("node_beta")
    static let roadAB = RoadID("alpha_beta")
    static let van = VehicleTypeID("test_van")
    static let product = ProductID("test_product")

    /// Two cities 100 km apart, one vehicle type (100 km/h), one product
    /// with a fixed 1000 kg mass so generated offers are fully predictable.
    static func catalog() throws -> GameCatalog {
        try GameCatalog(
            cities: [
                CityDefinition(id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST", latitude: 0, longitude: 0,
                               population: 100_000, hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                               costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: true),
                CityDefinition(id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST", latitude: 1, longitude: 0,
                               population: 100_000, hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                               costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: false)
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
                    coordinate: GeoCoordinate(latitude: 1, longitude: 0),
                    kind: .city,
                    cityID: cityB
                )
            ],
            roads: [
                RoadDefinition(
                    id: roadAB,
                    from: nodeA,
                    to: nodeB,
                    distanceKm: 100
                )
            ],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: van, name: "Test Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 2000, volumeM3: 20),
                    speedKmh: 100, purchasePrice: 10_000,
                    costPerKm: 0.5, driverCostPerHour: 10,
                    fixedCostPerDay: 60
                )
            ],
            products: [
                ProductDefinition(id: product, name: "Test Product", symbol: "shippingbox",
                                  densityM3PerTon: 2.0,
                                  minimumShipmentMassKg: 1000, maximumShipmentMassKg: 1000)
            ],
            cityMarkets: [
                CityMarketProfile(
                    cityID: cityA,
                    supply: [CityProductWeight(productID: product, weight: 10)],
                    demand: []
                ),
                CityMarketProfile(
                    cityID: cityB,
                    supply: [],
                    demand: [CityProductWeight(productID: product, weight: 10)]
                )
            ],
            economy: TestEconomy.make()
        )
    }

    static func newState(seed: UInt64 = 42) -> GameState {
        GameState.newCampaign(
            config: CampaignConfig(
                seed: seed,
                identity: CompanyIdentity(name: "Test Co", colorHex: "#1F6FEB", emblemSymbol: "star.fill"),
                hqCity: cityA
            ),
            economy: TestEconomy.make()
        )
    }

    /// The fixture's single derived lane: alpha's supplier → beta's receiver,
    /// 1500 kg/day (kept below the rate floor by the minimum-lanes rule).
    static let laneID = LaneID("\(cityA.rawValue).\(product.rawValue).\(cityB.rawValue)")

    /// Minutes of accrual ticks that guarantee the dock holds at least one
    /// 1000 kg parcel: even at the weekly swing's minimum (1125 kg/day,
    /// ~187 kg per 240-minute tick), eight ticks clear 1000 kg.
    static let minutesToFirstParcel = 8 * LaneConfig.tickMinutes

}

// MARK: - Engine rules

struct SimulationEngineTests {
    @Test func fixtureCatalogDerivesTheExpectedLane() throws {
        let catalog = try Fixture.catalog()
        let lane = try #require(catalog.lane(Fixture.laneID))
        #expect(lane.originCityID == Fixture.cityA)
        #expect(lane.destinationCityID == Fixture.cityB)
        #expect(lane.baseRatePerDayKg == 1_500)
        #expect(catalog.lanes.count == 1)
    }

    @Test func laneAccrualBuildsAndStaysWithinThePatienceWindow() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()

        // Nobody serves the lane: freight accrues, while the dock retains no
        // more than the patience window's production.
        engine.advance(&state, by: 14 * GameState.minutesPerDay)

        let lane = try #require(catalog.lane(Fixture.laneID))
        let cap = lane.baseRatePerDayKg * catalog.economy.lanes.parcelPatienceMinutes
            / GameState.minutesPerDay
        // The weekly swing moves the per-tick rate, so allow its amplitude.
        let swing = Double(catalog.economy.lanes.weeklySwingPercent) / 100
        let waiting = state.laneAccrualKg[Fixture.laneID] ?? 0
        #expect(waiting > 0)
        #expect(Double(waiting) <= Double(cap) * (1 + swing) + 1)

    }

    @Test func dispatchedVehicleShuttlesTheLaneAndSettlesAtSpotRate() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)
        #expect(vehicle.cityID == Fixture.cityA)

        // Let the dock fill past one parcel, then send the truck.
        engine.advance(&state, by: Fixture.minutesToFirstParcel)
        let waitingBefore = state.laneAccrualKg[Fixture.laneID] ?? 0
        #expect(waitingBefore >= 1_000)

        try engine.apply(
            .dispatchVehicleToLane(laneID: Fixture.laneID, vehicleID: vehicle.id),
            to: &state
        )
        let route = try #require(state.routes.first)
        #expect(route.isRunning)
        #expect(route.vehicleIDs == [vehicle.id])
        #expect(route.stops.map(\.task).contains(.pickupLane(Fixture.laneID)))
        #expect(route.stops.map(\.task).contains(.deliverLane(Fixture.laneID, .destination)))

        let cashBefore = state.cash
        // One lap: load (30), drive (60), unload (30) plus slack.
        engine.advance(&state, by: 6 * 60)

        #expect(state.stats.deliveredJobs >= 1)
        #expect(state.cash > cashBefore, "a served lane must clear its costs")
        // Parcel identity survived end to end: minted from the lane, carried
        // the supplier/receiver firms, settled at the spot rate.
        let deliveredLog = state.log.contains { entry in
            if case .routeShipmentDelivered(_, _, let destination, _) = entry.event {
                return destination == Fixture.cityB
            }
            return false
        }
        #expect(deliveredLog)
        // The shuttle keeps serving the lane: its run still exists (parked or
        // driving), it was not torn down after one delivery.
        #expect(state.routeRun(for: vehicle.id) != nil)
        // The dock was debited by what was loaded.
        let waitingAfter = state.laneAccrualKg[Fixture.laneID] ?? 0
        #expect(waitingAfter < waitingBefore + 1_000)
    }

    @Test func claimedLaneParcelIsPricedForTheLoadingVehicle() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        let vanType = try #require(catalog.vehicleType(Fixture.van))
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)

        engine.advance(&state, by: Fixture.minutesToFirstParcel)
        try engine.apply(
            .dispatchVehicleToLane(laneID: Fixture.laneID, vehicleID: vehicle.id),
            to: &state
        )
        // Service starts immediately (vehicle is already in alpha): parcels
        // exist as shipments claimed by the route.
        engine.advance(&state, by: 1)
        let shipment = try #require(state.shipments.first)
        #expect(shipment.offer.laneID == Fixture.laneID)
        let expected = engine.freightPayout(
            origin: Fixture.cityA,
            destination: Fixture.cityB,
            distanceKm: 100,
            load: shipment.offer.load,
            vehicleType: vanType,
            state: state
        )
        #expect(shipment.offer.payout == expected)
        let haul = engine.haulCost(
            origin: Fixture.cityA,
            destination: Fixture.cityB,
            distanceKm: 100,
            vehicleType: vanType
        )
        #expect(shipment.offer.payout > haul.cost, "spot price is cost plus margin by construction")
    }

    @Test func unaffordableVehicleIsRejected() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        #expect(state.cash == 10_000)
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        #expect(state.cash == 0)
        #expect(throws: CommandError.insufficientFunds(required: 10_000)) {
            try engine.apply(.buyVehicle(Fixture.van), to: &state)
        }
    }

    @Test func deletingRunningRouteFinishesLoadedCargoThenReleasesAndPurges() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)
        engine.advance(&state, by: Fixture.minutesToFirstParcel)
        try engine.apply(
            .dispatchVehicleToLane(laneID: Fixture.laneID, vehicleID: vehicle.id),
            to: &state
        )
        let routeID = try #require(state.routes.first?.id)

        engine.advance(&state, by: 0)
        engine.advance(&state, by: engine.loadingMinutes(at: Fixture.cityA))
        let loaded = try #require(state.shipments.first { $0.assignedRouteID == routeID })
        #expect(loaded.loadedVehicleID == vehicle.id)

        try engine.apply(.deleteRoute(routeID), to: &state)
        let cancelling = try #require(state.route(routeID))
        #expect(!cancelling.isRunning)
        #expect(cancelling.cancellationRequestedAt == state.clock)
        #expect(state.routeRun(for: vehicle.id)?.isWindingDown == true)

        engine.advance(&state, by: 500)

        #expect(state.route(routeID) == nil)
        #expect(state.routeRuns(of: routeID).isEmpty)
        #expect(state.shipments(of: routeID).isEmpty)
        #expect(state.vehicle(vehicle.id)?.cityID == Fixture.cityB)
        #expect(state.isVehicleIdle(vehicle.id))
        #expect(state.stats.deliveredJobs >= 1)
    }

    @Test func twoRouteVehiclesClaimDistinctLaneShipments() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        try engine.apply(.buyVehicle(Fixture.van), to: &state)

        let vehicles = state.vehicles
        #expect(vehicles.count == 2)
        try engine.apply(
            .dispatchVehicleToLane(laneID: Fixture.laneID, vehicleID: vehicles[0].id),
            to: &state
        )
        let route = try #require(state.routes.first)
        state.laneAccrualKg[Fixture.laneID] = 3_000
        try engine.apply(
            .assignVehicleToRoute(routeID: route.id, vehicleID: vehicles[1].id),
            to: &state
        )

        engine.advance(&state, by: 1)

        let runs = state.routeRuns(of: route.id)
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { !$0.claimedShipmentIDs.isEmpty })
        let claimedIDs = runs.flatMap(\.claimedShipmentIDs)
        #expect(claimedIDs.count == 3)
        #expect(Set(claimedIDs).count == claimedIDs.count)
    }

}

// MARK: - Determinism contract

struct DeterminismTests {
    private func encodedRouteState(chunks: [Int]) throws -> Data {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState(seed: 5_678)
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: Fixture.minutesToFirstParcel)
        let vehicle = try #require(state.vehicles.first)
        // A lane shuttle in the mix: dispatch claims parcels from the dock on
        // its own; the encoded state must still be chunk-invariant.
        try engine.apply(
            .dispatchVehicleToLane(laneID: Fixture.laneID, vehicleID: vehicle.id),
            to: &state
        )

        for chunk in chunks {
            engine.advance(&state, by: chunk)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    /// Same seed, same commands, same total game time -> byte-identical state,
    /// regardless of how the time advance is chunked.
    @Test func chunkedAdvanceMatchesSingleAdvance() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        func run(chunks: [Int]) throws -> Data {
            let engine = SimulationEngine(catalog: try Fixture.catalog())
            var state = Fixture.newState(seed: 1234)
            try engine.apply(.buyVehicle(Fixture.van), to: &state)
            // Let the dock fill, then serve the lane: accrual ticks, the claim,
            // pricing and capped accrual all sit on the determinism contract.
            engine.advance(&state, by: Fixture.minutesToFirstParcel)
            let vehicle = try #require(state.vehicles.first)
            try engine.apply(
                .dispatchVehicleToLane(laneID: Fixture.laneID, vehicleID: vehicle.id),
                to: &state
            )

            for chunk in chunks {
                engine.advance(&state, by: chunk)
            }
            return try encoder.encode(state)
        }

        let singleChunk = try run(chunks: [2000])
        let manyChunks = try run(chunks: Array(repeating: 100, count: 20))
        let unevenChunks = try run(chunks: [1, 999, 3, 497, 500])
        #expect(singleChunk == manyChunks)
        #expect(singleChunk == unevenChunks)
    }

    @Test func routeRunnerChunkedAdvanceMatchesSingleAdvance() throws {
        let singleChunk = try encodedRouteState(chunks: [2_000])
        let manyChunks = try encodedRouteState(chunks: Array(repeating: 100, count: 20))
        let unevenChunks = try encodedRouteState(chunks: [1, 999, 3, 497, 500])
        #expect(singleChunk == manyChunks)
        #expect(singleChunk == unevenChunks)
    }

    @Test func exactRouteEventDrainsSameTimeTransitions() throws {
        let exactBoundary = try encodedRouteState(chunks: [180])
        let trailingZeroAdvance = try encodedRouteState(chunks: [180, 0])
        #expect(exactBoundary == trailingZeroAdvance)
    }
}
