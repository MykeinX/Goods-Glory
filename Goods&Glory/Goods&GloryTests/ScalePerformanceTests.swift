//
//  ScalePerformanceTests.swift
//  Goods&GloryTests
//
//  A late-game campaign, built through real commands, timed against a budget.
//
//  The simulation ticks once per real second while the player watches the map,
//  so `advance` has a hard wall-clock budget that does not grow with the
//  empire. The danger is not any single slow function — it is the pattern of
//  looking something up with a linear scan inside a loop over another
//  collection, which is invisible at four vehicles and fatal at a thousand.
//
//  These tests exist so that pattern cannot come back unnoticed. If someone
//  reintroduces an O(n²) in the tick path, a test goes red instead of a
//  player's phone getting hot two years of development later.
//
//  OPT-IN: the suite builds several thousand-vehicle campaigns and takes
//  minutes, so it is skipped unless `GG_PERF=1` is set. Run it when touching
//  the engine, the map snapshot or `GameState`'s collections — not on every
//  edit.
//
//    Xcode:  Product ▸ Scheme ▸ Edit Scheme ▸ Test ▸ Arguments ▸
//            Environment Variables ▸ add GG_PERF = 1
//    CLI:    GG_PERF=1 xcodebuild test -scheme 'Goods&Glory' \
//              -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
//

import Foundation
import Testing
@testable import Goods_Glory

extension Trait where Self == ConditionTrait {
    /// Gates the slow benchmarks behind an environment flag so the everyday
    /// test cycle stays fast. A skipped test reports its reason, so nobody has
    /// to wonder why the suite looks empty.
    static var performanceOptIn: Self {
        .enabled(
            if: ProcessInfo.processInfo.environment["GG_PERF"] == "1",
            "Scale benchmarks are opt-in: set GG_PERF=1 to run them (several minutes)."
        )
    }
}

// MARK: - Synthetic late-game world

enum ScaleFixture {
    static let cityCount = 100
    static let product = ProductID("scale_product")
    static let truck = VehicleTypeID("scale_truck")

    static func cityID(_ index: Int) -> CityID { CityID("city_\(index)") }
    static func nodeID(_ index: Int) -> RoadNodeID { RoadNodeID("node_\(index)") }

    /// Cities on a ring, each linked to its neighbour, so every pair is
    /// reachable and path lengths stay realistic rather than degenerate.
    static func catalog(economy: EconomyConfig = TestEconomy.make()) throws -> GameCatalog {
        var cities: [CityDefinition] = []
        var nodes: [NetworkNodeDefinition] = []
        var roads: [RoadDefinition] = []
        var markets: [CityMarketProfile] = []

        for index in 0..<cityCount {
            let angle = Double(index) / Double(cityCount) * 2 * Double.pi
            let latitude = 20 * cos(angle)
            let longitude = 20 * sin(angle)
            cities.append(CityDefinition(
                id: cityID(index),
                roadNodeID: nodeID(index),
                name: "City \(index)",
                country: "TST",
                latitude: latitude,
                longitude: longitude,
                population: 200_000 + index * 10_000,
                hasRailFreightAccess: false,
                hasAirCargoAccess: false,
                hasSeaPortAccess: false,
                // Founding cost is costIndex × 40 and must leave room for an
                // entry vehicle out of starting cash, so keep it at the floor.
                costIndex: 250,
                trafficDelayIndex: 1_000,
                isStarterCity: index == 0
            ))
            nodes.append(NetworkNodeDefinition(
                id: nodeID(index),
                coordinate: GeoCoordinate(latitude: latitude, longitude: longitude),
                kind: .city,
                cityID: cityID(index)
            ))
            // Every city both supplies and demands, so lane derivation has
            // work to do everywhere — the realistic late-game shape.
            markets.append(CityMarketProfile(
                cityID: cityID(index),
                supply: [CityProductWeight(productID: product, weight: 10)],
                demand: [CityProductWeight(productID: product, weight: 10)]
            ))
        }

        for index in 0..<cityCount {
            let next = (index + 1) % cityCount
            roads.append(RoadDefinition(
                id: RoadID("road_\(index)_\(next)"),
                from: nodeID(index),
                to: nodeID(next),
                distanceKm: 120
            ))
        }

        return try GameCatalog(
            cities: cities,
            networkNodes: nodes,
            roads: roads,
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: truck, name: "Scale Truck", symbol: "box.truck",
                    capacity: LoadSize(massKg: 20_000, volumeM3: 80),
                    speedKmh: 80, purchasePrice: 10_000,
                    costPerKm: 0.5, driverCostPerHour: 10,
                    fixedCostPerDay: 60
                )
            ],
            products: [
                ProductDefinition(
                    id: product, name: "Scale Product", symbol: "shippingbox",
                    densityM3PerTon: 2.0,
                    minimumShipmentMassKg: 1_000, maximumShipmentMassKg: 2_000
                )
            ],
            cityMarkets: markets,
            economy: economy
        )
    }

    /// A campaign the size we intend to support: a thousand trucks spread over
    /// a hundred routes, branches everywhere, and enough simulated days for
    /// cargo to actually be in flight.
    ///
    /// Built with real commands rather than hand-assembled structs, so the
    /// engine walks the same code paths it would in a real save. A hand-built
    /// state can be quietly invalid and make a benchmark measure nothing.
    /// - Parameter activeLanes: how many standing freight lanes to crew. These
    ///   routes exercise dock claims, shipment movement and delivery settlement;
    ///   plain travel routes exercise only the cheaper movement path.
    static func campaign(
        vehicles vehicleCount: Int = 1_000,
        routes routeCount: Int = 100,
        activeLanes laneCount: Int = 0,
        warmUpDays: Int = 4
    ) throws -> (engine: SimulationEngine, state: GameState) {
        let catalog = try catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = GameState.newCampaign(
            config: CampaignConfig(seed: 20_260_719, identity: identity, hqCity: cityID(0)),
            economy: catalog.economy
        )
        // Financing is not what is under test.
        state.cash = 1_000_000_000

        for index in 0..<cityCount where index != 0 {
            try engine.apply(.installModule(kind: .office, cityID: cityID(index)), to: &state)
        }
        for index in stride(from: 0, to: cityCount, by: 4) {
            try engine.apply(.installModule(kind: .warehouse, cityID: cityID(index)), to: &state)
        }
        // Let construction land and standing lanes accrue freight.
        engine.advance(&state, by: 3 * GameState.minutesPerDay)

        for _ in 0..<vehicleCount {
            try engine.apply(.buyVehicle(truck), to: &state)
        }

        var freeVehicles = state.vehicles.map(\.id)[...]

        // Crew standing freight lanes first: these are the routes that move cargo.
        for lane in catalog.lanes.prefix(laneCount) {
            guard let vehicleID = freeVehicles.first else { break }
            freeVehicles = freeVehicles.dropFirst()
            try engine.apply(
                .dispatchVehicleToLane(laneID: lane.id, vehicleID: vehicleID),
                to: &state
            )
        }

        // Ring routes for whatever fleet the freight lanes did not consume.
        // Never more routes than there are trucks left to crew them: an empty
        // route cannot be started (`noVehicleAssigned`), and heavy crewing
        // ratios can legitimately leave almost nothing spare.
        let travelRouteCount = min(routeCount, freeVehicles.count)
        var routeIDs: [RouteID] = []
        for routeIndex in 0..<travelRouteCount {
            try engine.apply(.createRoute(name: "R\(routeIndex)"), to: &state)
            guard let routeID = state.routes.last?.id else { continue }
            routeIDs.append(routeID)
            for step in 0..<4 {
                let city = cityID((routeIndex + step * 7) % cityCount)
                try engine.apply(.addTravelStop(routeID: routeID, cityID: city), to: &state)
            }
        }

        // Only vehicles not already crewing a freight lane.
        if !routeIDs.isEmpty {
            for (offset, vehicleID) in freeVehicles.enumerated() {
                let routeID = routeIDs[offset % routeIDs.count]
                try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicleID), to: &state)
            }
            for routeID in routeIDs {
                try engine.apply(.startRoute(routeID), to: &state)
            }
        }

        precondition(
            state.routes.contains { $0.isRunning },
            "scale fixture produced no running routes"
        )

        // Warm up so shipments and runs reach a steady state. A tick
        // measured on an empty world measures nothing.
        engine.advance(&state, by: warmUpDays * GameState.minutesPerDay)
        return (engine, state)
    }

    /// Everything the engine has to reason about per parcel: cargo in flight or
    /// storage.
    static func parcelsInNetwork(_ state: GameState) -> Int {
        state.shipments.count
    }

    private static let identity = CompanyIdentity(
        name: "Scale Freight",
        colorHex: "#FFB037",
        emblemSymbol: "shippingbox.fill"
    )
}

// MARK: - Measurement

/// Median rather than mean: one scheduler hiccup should not decide whether the
/// build is red. Monotonic clock so a clock adjustment cannot skew a sample.
private func medianMilliseconds(iterations: Int, _ body: () -> Void) -> Double {
    let clock = ContinuousClock()
    var samples: [Double] = []
    samples.reserveCapacity(iterations)
    for _ in 0..<iterations {
        let elapsed = clock.measure { body() }
        samples.append(Double(elapsed.components.attoseconds) / 1e15
            + Double(elapsed.components.seconds) * 1000)
    }
    samples.sort()
    return samples[samples.count / 2]
}

// MARK: - Budgets

@Suite("Scale performance", .serialized, .performanceOptIn)
struct ScalePerformanceTests {
    /// One simulated tick at 1x speed. Ticks fire once per real second and the
    /// main thread also has to render, so this is generous by design: it is a
    /// regression alarm, not a target.
    ///
    /// Deliberately loose enough to survive an unoptimised debug build and a
    /// busy CI machine. A genuine O(n²) regression overshoots it by orders of
    /// magnitude, not by a few percent.
    static let tickBudgetMilliseconds: Double = 50
    /// A whole simulated day in one call — what a speed-up or a resume does.
    static let dayBudgetMilliseconds: Double = 900

    @Test("A 1000-vehicle tick stays inside the frame budget")
    func tickAtScale() throws {
        var (engine, state) = try ScaleFixture.campaign()

        // Guard the fixture itself: a benchmark that silently degenerated into
        // an empty world would pass forever while measuring nothing.
        #expect(state.vehicles.count == 1_000)
        #expect(state.routeRuns.count > 500, "expected most of the fleet to be running")

        let median = medianMilliseconds(iterations: 20) {
            engine.advance(&state, by: 5) // 1x speed: 5 game minutes per second
        }
        #expect(
            median < Self.tickBudgetMilliseconds,
            "tick took \(median) ms at 1000 vehicles (budget \(Self.tickBudgetMilliseconds) ms)"
        )
    }

    @Test("A simulated day at scale stays inside the catch-up budget")
    func dayAtScale() throws {
        var (engine, state) = try ScaleFixture.campaign()
        let median = medianMilliseconds(iterations: 3) {
            engine.advance(&state, by: GameState.minutesPerDay)
        }
        #expect(
            median < Self.dayBudgetMilliseconds,
            "one simulated day took \(median) ms at 1000 vehicles (budget \(Self.dayBudgetMilliseconds) ms)"
        )
    }

    // MARK: Cargo path
    //
    // The tests above run a fleet on plain travel stops, which never enters the
    // parts of `beginService` that claim parcels and check warehouses. Those
    // paths have their own linear scans, so
    // they get their own fixture — otherwise the suite would report a healthy
    // engine while the expensive half went unmeasured.

    /// Freight a fully crewed network sustains — measured, not wished for.
    ///
    /// Crewed lanes claim freight continuously, so steady-state parcels track
    /// the active lane count rather than simulated time.
    static let sustainedParcelFloor = 60

    @Test("A cargo-carrying fleet stays inside the tick budget")
    func cargoTickAtScale() throws {
        var (engine, state) = try ScaleFixture.campaign(activeLanes: 200, warmUpDays: 21)

        let parcels = ScaleFixture.parcelsInNetwork(state)
        #expect(
            parcels >= Self.sustainedParcelFloor,
            "only \(parcels) parcels across \(state.routes.count) routes — the cargo path is not being exercised"
        )

        let median = medianMilliseconds(iterations: 20) {
            engine.advance(&state, by: 5)
        }
        #expect(
            median < Self.tickBudgetMilliseconds,
            "cargo tick took \(median) ms with \(parcels) parcels (budget \(Self.tickBudgetMilliseconds) ms)"
        )
    }


    /// Scales the freight itself, not the fleet.
    @Test("Cargo tick cost grows linearly with freight volume")
    func cargoScalesLinearly() throws {
        func sample(activeLanes: Int) throws -> (milliseconds: Double, parcels: Int) {
            var (engine, state) = try ScaleFixture.campaign(
                activeLanes: activeLanes,
                warmUpDays: 21
            )
            let parcels = ScaleFixture.parcelsInNetwork(state)
            let median = medianMilliseconds(iterations: 15) {
                engine.advance(&state, by: 5)
            }
            return (median, parcels)
        }

        let few = try sample(activeLanes: 50)
        let many = try sample(activeLanes: 200)

        // Compare against the freight volume actually achieved, not the lanes
        // requested — the economy decides how much cargo a lane count produces.
        let parcelGrowth = Double(many.parcels) / Double(max(few.parcels, 1))
        let timeGrowth = many.milliseconds / max(few.milliseconds, 0.0001)

        #expect(parcelGrowth > 1.5, "freight volume barely grew (\(few.parcels) → \(many.parcels)) — inconclusive")
        #expect(
            timeGrowth < parcelGrowth * 2,
            "tick cost grew \(timeGrowth)x while freight grew \(parcelGrowth)x (\(few.milliseconds) ms / \(few.parcels) parcels → \(many.milliseconds) ms / \(many.parcels) parcels)"
        )
    }

    /// The real defence. Absolute timings drift with hardware and build
    /// configuration; the *shape* of the curve does not. Doubling the fleet
    /// should roughly double the tick cost, never quadruple it.
    @Test("Tick cost grows linearly, not quadratically, with fleet size")
    func tickScalesLinearly() throws {
        func medianTick(vehicles: Int) throws -> Double {
            var (engine, state) = try ScaleFixture.campaign(vehicles: vehicles, routes: 100)
            return medianMilliseconds(iterations: 15) {
                engine.advance(&state, by: 5)
            }
        }

        let small = try medianTick(vehicles: 250)
        let large = try medianTick(vehicles: 1_000)

        // 4x the fleet. Linear would be ~4x, quadratic ~16x. Allowing 8x leaves
        // room for measurement noise and fixed overheads while still failing
        // loudly on a reintroduced quadratic.
        let growth = large / max(small, 0.0001)
        #expect(
            growth < 8,
            "tick cost grew \(growth)x for a 4x fleet — that curve is superlinear (small \(small) ms, large \(large) ms)"
        )
    }
}
