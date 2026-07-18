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
                               costIndex: 1_000, trafficDelayIndex: 1_000, isStarterCity: true),
                CityDefinition(id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST", latitude: 1, longitude: 0,
                               population: 100_000, hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                               costIndex: 1_000, trafficDelayIndex: 1_000, isStarterCity: false)
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
                    distanceKm: 100,
                    geometry: [
                        GeoCoordinate(latitude: 0, longitude: 0),
                        GeoCoordinate(latitude: 1, longitude: 0)
                    ]
                )
            ],
            vehicleTypes: [
                VehicleTypeDefinition(id: van, name: "Test Van", symbol: "box.truck",
                                      capacity: LoadSize(massKg: 2000, volumeM3: 20),
                                      speedKmh: 100, purchasePrice: 10_000,
                                      costPerKm: 0.5, driverCostPerHour: 10)
            ],
            products: [
                ProductDefinition(id: product, name: "Test Product", symbol: "shippingbox",
                                  densityM3PerTon: 2.0,
                                  minimumShipmentMassKg: 1000, maximumShipmentMassKg: 1000)
            ],
            cityMarkets: [
                CityMarketProfile(cityID: cityA, supply: [], demand: []),
                CityMarketProfile(cityID: cityB, supply: [], demand: [])
            ],
            economy: EconomyConfig(
                startingCash: 20_000,
                loadingMinutes: 30,
                unloadingMinutes: 30,
                offerGenerationIntervalMinutes: 480,
                offerLifetimeMinutes: 720,
                offerChancePercent: 100,
                maxOpenOffersPerCity: 3,
                offerMinimumProfit: 100,
                offerProfitMarginPercent: 20
            )
        )
    }

    static func newState(seed: UInt64 = 42) -> GameState {
        GameState.newCampaign(
            config: CampaignConfig(
                seed: seed,
                identity: CompanyIdentity(name: "Test Co", colorHex: "#1F6FEB", emblemSymbol: "star.fill"),
                hqCity: cityA
            ),
            economy: EconomyConfig(
                startingCash: 20_000,
                loadingMinutes: 30,
                unloadingMinutes: 30,
                offerGenerationIntervalMinutes: 480,
                offerLifetimeMinutes: 720,
                offerChancePercent: 100,
                maxOpenOffersPerCity: 3,
                offerMinimumProfit: 100,
                offerProfitMarginPercent: 20
            )
        )
    }
}

// MARK: - Engine rules

struct SimulationEngineTests {
    @Test func bundledInitialOffersAreLocalCarryableRegionalAndCostBased() throws {
        let catalog = try GameCatalog.load(from: .main)
        let engine = SimulationEngine(catalog: catalog)
        let entryVehicleType = try #require(catalog.vehicleTypes
            .filter { $0.purchasePrice <= catalog.economy.startingCash }
            .min {
                $0.purchasePrice == $1.purchasePrice
                    ? $0.id.rawValue < $1.id.rawValue
                    : $0.purchasePrice < $1.purchasePrice
            })
        let headquarters = catalog.starterCities.map(\.id).sorted { $0.rawValue < $1.rawValue }
        #expect(headquarters.count >= 6)

        for hqCity in headquarters {
            let nearbyCities = Set(catalog.nearestCities(from: hqCity, limit: 5))
            for seed in UInt64(0)..<20 {
                var state = GameState.newCampaign(
                    config: CampaignConfig(
                        seed: seed,
                        identity: CompanyIdentity(
                            name: "Test Co", colorHex: "#1F6FEB", emblemSymbol: "star.fill"
                        ),
                        hqCity: hqCity
                    ),
                    economy: catalog.economy
                )

                engine.advance(&state, by: 0)

                #expect(!state.offers.isEmpty)
                #expect(state.offers.count <= catalog.economy.maxOpenOffersPerCity)
                for offer in state.offers {
                    let product = try #require(catalog.product(offer.productID))
                    #expect(offer.origin == hqCity)
                    #expect(nearbyCities.contains(offer.destination))
                    #expect(offer.load.fits(in: entryVehicleType.capacity))
                    #expect(offer.load.massKg % ProductDefinition.shipmentMassStepKg == 0)
                    #expect((product.minimumShipmentMassKg...product.maximumShipmentMassKg)
                        .contains(offer.load.massKg))

                    let expectedVolume = (
                        Double(offer.load.massKg) / 1000 * product.densityM3PerTon * 10
                    ).rounded() / 10
                    #expect(offer.load.volumeM3 == expectedVolume)

                    let directMinutes = catalog.economy.loadingMinutes
                        + engine.travelMinutes(
                            distanceKm: offer.distanceKm,
                            speedKmh: entryVehicleType.speedKmh
                        )
                        + catalog.economy.unloadingMinutes
                    let directCost = engine.taskCost(
                        totalKm: offer.distanceKm,
                        taskMinutes: directMinutes,
                        vehicleType: entryVehicleType
                    )
                    let percentageProfit = Money((
                        Double(directCost)
                            * Double(catalog.economy.offerProfitMarginPercent) / 100
                    ).rounded())
                    #expect(offer.payout == directCost + max(
                        catalog.economy.offerMinimumProfit,
                        percentageProfit
                    ))
                }
            }
        }
    }

    @Test func offersFollowAnAvailableVehicleLocation() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        state.vehicles.append(Vehicle(
            id: VehicleID(rawValue: 999),
            typeID: Fixture.van,
            cityID: Fixture.cityB,
            assignedJobID: nil,
            odometerKm: 0
        ))

        engine.advance(&state, by: 0)

        #expect(!state.offers.isEmpty)
        #expect(state.offers.allSatisfy { $0.origin == Fixture.cityB })
        #expect(state.offers.allSatisfy { $0.load.massKg == 1_000 })
    }

    @Test func fullJobLifecycleSettlesCorrectly() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()

        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        #expect(state.cash == 10_000)
        let vehicle = try #require(state.vehicles.first)
        #expect(vehicle.cityID == Fixture.cityA)

        engine.advance(&state, by: 0) // initial offer batch
        let offer = try #require(state.offers.first { $0.origin == Fixture.cityA })
        // Fixed generation values: 1000 kg over 100 km.
        #expect(offer.load.massKg == 1000)
        #expect(offer.payout == 170) // $70 direct cost + $100 minimum profit.

        try engine.apply(.acceptJob(offerID: offer.id, vehicleID: vehicle.id), to: &state)
        #expect(state.activeJobs.count == 1)
        #expect(state.activeJobs[0].phase == .loading) // vehicle already at origin, no deadhead
        #expect(state.activeJobs[0].route == [
            RoadTraversal(roadID: Fixture.roadAB, direction: .forward)
        ])

        // 30 loading + 60 driving + 30 unloading = 120 minutes.
        engine.advance(&state, by: 120)
        #expect(state.activeJobs.isEmpty)

        let delivered = try #require(state.vehicles.first)
        #expect(delivered.cityID == Fixture.cityB) // vehicle stays at destination
        #expect(delivered.isAvailable)
        #expect(abs(delivered.odometerKm - 100) < 0.001)

        // Cost: 100 km * 0.5 + 2 h * 10 = 70. Cash: 10000 + 170 - 70.
        #expect(state.cash == 10_100)
        #expect(state.stats.deliveredJobs == 1)
    }

    @Test func oversizedLoadIsRejected() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)

        let oversized = JobOffer(
            id: JobID(rawValue: 999),
            origin: Fixture.cityA,
            destination: Fixture.cityB,
            productID: Fixture.product,
            load: LoadSize(massKg: 5000, volumeM3: 5),
            payout: 1000,
            distanceKm: 100,
            createdAt: state.clock,
            expiresAt: state.clock + 720
        )
        state.offers.append(oversized)

        #expect(throws: CommandError.loadExceedsCapacity) {
            try engine.apply(.acceptJob(offerID: oversized.id, vehicleID: vehicle.id), to: &state)
        }
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

    @Test func expiredOffersAreRemoved() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        engine.advance(&state, by: 0)
        #expect(!state.offers.isEmpty)
        let firstBatchIDs = Set(state.offers.map(\.id))

        engine.advance(&state, by: 720) // past first batch lifetime
        #expect(state.offers.allSatisfy { !firstBatchIDs.contains($0.id) })
    }
}

// MARK: - Determinism contract

struct DeterminismTests {
    /// Same seed, same commands, same total game time -> byte-identical state,
    /// regardless of how the time advance is chunked.
    @Test func chunkedAdvanceMatchesSingleAdvance() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        func run(chunks: [Int]) throws -> Data {
            let engine = SimulationEngine(catalog: try Fixture.catalog())
            var state = Fixture.newState(seed: 1234)
            try engine.apply(.buyVehicle(Fixture.van), to: &state)
            engine.advance(&state, by: 0)

            let offer = try #require(state.offers.first { $0.origin == Fixture.cityA })
            let vehicle = try #require(state.vehicles.first)
            try engine.apply(.acceptJob(offerID: offer.id, vehicleID: vehicle.id), to: &state)

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
}
