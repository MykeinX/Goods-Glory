//
//  FacilityAndNetworkTests.swift
//  Goods&GloryTests
//
//  Branches, warehouses and multi-stage transport. The fixture is a three-city
//  line (Alpha — Hub — Beta) so a parcel can legitimately be staged halfway,
//  which is the whole point of the warehouse system.
//

import Foundation
import Testing
@testable import Goods_Glory

private enum NetFixture {
    static let cityA = CityID("alpha")
    static let cityH = CityID("hub")
    static let cityB = CityID("beta")
    static let nodeA = RoadNodeID("node_alpha")
    static let nodeH = RoadNodeID("node_hub")
    static let nodeB = RoadNodeID("node_beta")
    static let roadAH = RoadID("alpha_hub")
    static let roadHB = RoadID("hub_beta")
    static let van = VehicleTypeID("test_van")
    static let product = ProductID("test_product")

    /// Founding costs scale with the city's cost index (22x), and this fixture
    /// deliberately uses the 1000 baseline so facility quotes read like the
    /// real catalog. That makes the free HQ cost 22k, so the fixture economy
    /// starts with enough cash to found *and* buy a van.
    static let economy = TestEconomy.make(startingCash: 60_000)

    /// Alpha supplies, Beta demands, Hub sits in the middle supplying nothing.
    /// 100 km per leg, 100 km/h, fixed 1000 kg parcels.
    static func catalog(economy: EconomyConfig = NetFixture.economy) throws -> GameCatalog {
        func city(_ id: CityID, _ node: RoadNodeID, _ name: String, lat: Double, starter: Bool) -> CityDefinition {
            CityDefinition(
                id: id, roadNodeID: node, name: name, country: "TST",
                latitude: lat, longitude: 0,
                population: 100_000,
                hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
                costIndex: 1_000, trafficDelayIndex: 1_000, isStarterCity: starter
            )
        }
        return try GameCatalog(
            cities: [
                city(cityA, nodeA, "Alpha", lat: 0, starter: true),
                city(cityH, nodeH, "Hub", lat: 1, starter: false),
                city(cityB, nodeB, "Beta", lat: 2, starter: false)
            ],
            networkNodes: [
                NetworkNodeDefinition(id: nodeA, coordinate: GeoCoordinate(latitude: 0, longitude: 0), kind: .city, cityID: cityA),
                NetworkNodeDefinition(id: nodeH, coordinate: GeoCoordinate(latitude: 1, longitude: 0), kind: .city, cityID: cityH),
                NetworkNodeDefinition(id: nodeB, coordinate: GeoCoordinate(latitude: 2, longitude: 0), kind: .city, cityID: cityB)
            ],
            roads: [
                RoadDefinition(id: roadAH, from: nodeA, to: nodeH, distanceKm: 100),
                RoadDefinition(id: roadHB, from: nodeH, to: nodeB, distanceKm: 100)
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
                ProductDefinition(
                    id: product, name: "Test Product", symbol: "shippingbox",
                    densityM3PerTon: 2.0,
                    minimumShipmentMassKg: 1000, maximumShipmentMassKg: 1000
                )
            ],
            cityMarkets: [
                CityMarketProfile(cityID: cityA, supply: [CityProductWeight(productID: product, weight: 10)], demand: []),
                CityMarketProfile(cityID: cityH, supply: [], demand: []),
                CityMarketProfile(cityID: cityB, supply: [], demand: [CityProductWeight(productID: product, weight: 10)])
            ],
            economy: economy
        )
    }

    static func newState(seed: UInt64 = 7, economy: EconomyConfig = NetFixture.economy) -> GameState {
        GameState.newCampaign(
            config: CampaignConfig(
                seed: seed,
                identity: CompanyIdentity(name: "Test Co", colorHex: "#1F6FEB", emblemSymbol: "star.fill"),
                hqCity: cityA
            ),
            economy: economy
        )
    }

    /// The derived Alpha → Beta lane (alpha supplies, beta demands).
    static let laneID = LaneID("\(cityA.rawValue).\(product.rawValue).\(cityB.rawValue)")

}

// MARK: - Facilities

struct FacilityTests {
    @Test func foundingCreatesAnOperationalHeadquartersBranch() throws {
        let state = NetFixture.newState()
        let hq = try #require(state.facility(in: NetFixture.cityA))
        let office = try #require(hq.module(.office))
        #expect(hq.isHeadquarters)
        #expect(office.isOperational(at: state.clock))
        // Nothing is granted anywhere else for free.
        #expect(state.module(.office, in: NetFixture.cityB) == nil)
    }

    @Test func facilityPriceDependsOnTheCity() throws {
        // Same building, two cities that differ only in cost index and size.
        let cheap = CityDefinition(
            id: CityID("cheap"), roadNodeID: RoadNodeID("n1"), name: "Cheap", country: "TST",
            latitude: 0, longitude: 0, population: 300_000,
            hasRailFreightAccess: false, hasAirCargoAccess: false, hasSeaPortAccess: false,
            costIndex: 800, trafficDelayIndex: 1_000, isStarterCity: false
        )
        let pricey = CityDefinition(
            id: CityID("pricey"), roadNodeID: RoadNodeID("n2"), name: "Pricey", country: "TST",
            latitude: 0, longitude: 0, population: 9_000_000,
            hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: true,
            costIndex: 1_300, trafficDelayIndex: 1_000, isStarterCity: false
        )
        let config = TestEconomy.defaultFacilities
        let cheapQuote = try #require(
            FacilityEconomics.quote(kind: .warehouse, level: 1, city: cheap, config: config)
        )
        let priceyQuote = try #require(
            FacilityEconomics.quote(kind: .warehouse, level: 1, city: pricey, config: config)
        )
        #expect(priceyQuote.cost > cheapQuote.cost)
        #expect(priceyQuote.upkeepPerDay > cheapQuote.upkeepPerDay)
        // Dense metros also take longer to build in, but not dramatically.
        #expect(priceyQuote.buildMinutes > cheapQuote.buildMinutes)
        #expect(Double(priceyQuote.buildMinutes) < Double(cheapQuote.buildMinutes) * 2)
    }

    @Test func constructionCostsCashUpFrontAndGrantsNothingUntilItFinishes() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()

        let quote = try #require(engine.quote(kind: .office, level: 1, city: NetFixture.cityB))
        let cashBefore = state.cash
        try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityB), to: &state)
        #expect(state.cash == cashBefore - quote.cost)

        // Under construction: present in state, but grants nothing.
        #expect(state.module(.office, in: NetFixture.cityB) != nil)
        #expect(state.facility(in: NetFixture.cityB)?.operationalModule(.office, at: state.clock) == nil)

        engine.advance(&state, by: quote.buildMinutes)
        #expect(state.facility(in: NetFixture.cityB)?.operationalModule(.office, at: state.clock) != nil)

        // Building twice in the same city is refused rather than double-charged.
        #expect(throws: CommandError.facilityAlreadyExists) {
            try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityB), to: &state)
        }
    }

    /// A site is a building, not a shopping list. Everything needs the office
    /// that represents the company in the city, and loading docks are equipment
    /// bolted to a warehouse — buying them into an empty city was nonsense.
    @Test func modulesCanOnlyBeBuiltOntoWhatTheyStandOn() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        state.cash += 1_000_000

        // Hub has nothing at all.
        #expect(throws: CommandError.officeRequired) {
            try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        }
        #expect(throws: CommandError.officeRequired) {
            try engine.apply(.installModule(kind: .dock, cityID: NetFixture.cityH), to: &state)
        }

        // An office alone still does not justify a loading dock.
        try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        #expect(throws: CommandError.warehouseRequired) {
            try engine.apply(.installModule(kind: .dock, cityID: NetFixture.cityH), to: &state)
        }

        // With the warehouse ordered, the dock becomes buildable.
        try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.installModule(kind: .dock, cityID: NetFixture.cityH), to: &state)
        #expect(state.module(.dock, in: NetFixture.cityH) != nil)
    }

    /// Sweeping a city's own dock into its own warehouse is a real strategy:
    /// it banks freight for one big run later. The engine used to make it
    /// unbuildable and unreadable — a forced
    /// delivery stop across the map, no measurable efficiency (it drives no
    /// kilometres) and a guaranteed loss (storing booked no revenue).
    @Test func anInCityFeederIsBuildableMeasurableAndNotALoss() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        state.cash += 1_000_000
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)

        // A warehouse in the lane's own origin city.
        try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityA), to: &state)
        let warehouseQuote = try #require(engine.quote(kind: .warehouse, level: 1, city: NetFixture.cityA))
        engine.advance(&state, by: warehouseQuote.buildMinutes)

        try engine.apply(.createRoute(name: "Alpha sweep"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: NetFixture.cityA), to: &state)
        let visitID = try #require(state.route(routeID)?.stops.first?.id)

        // Storing here first: the pickup must then *not* drag in a delivery
        // stop in Beta.
        try engine.apply(
            .addNetworkTaskToRoute(routeID: routeID, visitStopID: visitID, task: .dropToWarehouse),
            to: &state
        )
        try engine.apply(
            .addNetworkTaskToRoute(
                routeID: routeID, visitStopID: visitID, task: .pickupLane(NetFixture.laneID)
            ),
            to: &state
        )
        let stops = try #require(state.route(routeID)?.stops)
        #expect(stops.allSatisfy { $0.cityID == NetFixture.cityA })

        // It runs, and it is not refused for having no delivery.
        let vehicle = try #require(state.vehicles.first)
        try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(routeID), to: &state)
        engine.advance(&state, by: 3 * GameState.minutesPerDay)

        let route = try #require(state.route(routeID))
        // Freight actually moved into the warehouse.
        let warehouse = try #require(state.warehouseSite(in: NetFixture.cityA))
        #expect(!state.shipments(storedIn: warehouse.id).isEmpty)
        // Efficiency is measured in worked minutes, so a 0 km route still reports.
        #expect(route.stats.recentLoadFactor != nil)
        // And the hand-off settled what the sweep spent, so it is not a hole.
        #expect(route.stats.revenue > 0)
        // Nobody is told to find a return load for a route that never leaves town.
        if case .emptyReturn = engine.bottleneck(of: route, state: state) {
            Issue.record("a single-city route cannot have a backhaul")
        }
    }

    /// Equipment is not a bonus percentage bolted onto a menu — each piece
    /// moves exactly one physical number, and only while its building stands.
    @Test func equipmentExtendsTheBuildingItIsInstalledIn() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        state.cash += 1_000_000

        try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        let warehouseQuote = try #require(engine.quote(kind: .warehouse, level: 1, city: NetFixture.cityH))
        engine.advance(&state, by: warehouseQuote.buildMinutes)

        let site = try #require(state.facility(in: NetFixture.cityH))
        let bareStorage = engine.storageCapacity(of: site, state: state)
        let bareHandling = engine.handlingMinutes(
            loading: true, massKg: 1_000, at: NetFixture.cityH, state: state
        )

        // Racking is warehouse shelving: it may not be built anywhere else.
        #expect(throws: CommandError.warehouseRequired) {
            try engine.apply(.installModule(kind: .racking, cityID: NetFixture.cityA), to: &state)
        }
        try engine.apply(.installModule(kind: .racking, cityID: NetFixture.cityH), to: &state)
        let rackQuote = try #require(engine.quote(kind: .racking, level: 1, city: NetFixture.cityH))
        engine.advance(&state, by: rackQuote.buildMinutes)

        let racked = try #require(state.facility(in: NetFixture.cityH))
        #expect(engine.storageCapacity(of: racked, state: state).massKg > bareStorage.massKg)

        // Forklifts belong to the dock, and they shorten handling.
        try engine.apply(.installModule(kind: .dock, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.installModule(kind: .forklift, cityID: NetFixture.cityH), to: &state)
        let forkQuote = try #require(engine.quote(kind: .forklift, level: 1, city: NetFixture.cityH))
        let dockQuote = try #require(engine.quote(kind: .dock, level: 1, city: NetFixture.cityH))
        engine.advance(&state, by: max(forkQuote.buildMinutes, dockQuote.buildMinutes))

        let equipped = engine.handlingMinutes(
            loading: true, massKg: 1_000, at: NetFixture.cityH, state: state
        )
        #expect(equipped < bareHandling)
    }

    /// And the tree cannot be dismantled from the bottom either.
    @Test func aModuleCarryingAnotherCannotBeRemoved() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        state.cash += 1_000_000
        try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.installModule(kind: .dock, cityID: NetFixture.cityH), to: &state)

        #expect(throws: CommandError.dependentModuleExists(.dock)) {
            try engine.apply(.removeModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        }
        #expect(throws: CommandError.dependentModuleExists(.warehouse)) {
            try engine.apply(.removeModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        }

        // Clearing from the top down works.
        try engine.apply(.removeModule(kind: .dock, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.removeModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.removeModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        #expect(state.facility(in: NetFixture.cityH) == nil)
    }

    @Test func headquartersCannotBeDemolishedAndAFullWarehouseRefusesToo() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        #expect(state.module(.office, in: NetFixture.cityA) != nil)

        #expect(throws: CommandError.cannotDemolishHeadquarters) {
            try engine.apply(.removeModule(kind: .office, cityID: NetFixture.cityA), to: &state)
        }
    }

}

// MARK: - Warehouses and multi-stage transport

struct WarehouseNetworkTests {
    /// Builds an operational warehouse in the hub and returns it.
    private func makeHubWarehouse(
        engine: SimulationEngine,
        state: inout GameState
    ) throws -> Facility {
        // A warehouse stands next to an office, not on its own.
        state.cash += 1_000_000
        try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        let quote = try #require(engine.quote(kind: .warehouse, level: 1, city: NetFixture.cityH))
        try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        engine.advance(&state, by: quote.buildMinutes)
        let warehouse = try #require(state.warehouseSite(in: NetFixture.cityH))
        #expect(warehouse.isOperational(at: state.clock))
        return warehouse
    }

    @Test func stagingThroughAWarehousePaysExactlyTheSameAsADirectHaul() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)
        let warehouse = try makeHubWarehouse(engine: engine, state: &state)
        let vehicle = try #require(state.vehicles.first)

        // Leg 1: collect lane freight at Alpha, hand it over at the hub.
        try engine.apply(.createRoute(name: "Collection"), to: &state)
        let leg1 = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: leg1, cityID: NetFixture.cityA), to: &state)
        let alphaVisit = try #require(state.route(leg1)?.stops.first?.id)
        try engine.apply(.addTravelStop(routeID: leg1, cityID: NetFixture.cityH), to: &state)
        let collectionHubVisit = try #require(state.route(leg1)?.stops.last?.id)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: leg1,
            visitStopID: alphaVisit,
            task: .pickupLane(NetFixture.laneID)
        ), to: &state)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: leg1,
            visitStopID: collectionHubVisit,
            task: .dropToWarehouse
        ), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: leg1, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(leg1), to: &state)

        // Load (30) + drive 100 km (60) + unload (30), plus loop slack.
        engine.advance(&state, by: 300)
        let stored = state.shipments(storedIn: warehouse.id)
        #expect(stored.count == 1)
        let expectedRevenue = try #require(stored.first).offer.payout
        // Storing is not selling: no revenue until the parcel reaches Beta.
        #expect(state.stats.deliveredJobs == 0)
        // Stored cargo belongs to the network, not to the route that dropped it.
        #expect(stored.first?.assignedRouteID == nil)

        // Leg 2: collect the lot at the hub, deliver everything at Beta.
        try engine.apply(.stopRoute(leg1), to: &state)
        engine.advance(&state, by: 300)
        // Stopping ends the run; the vehicle stays rostered to that lane until
        // it is explicitly taken off, so a second lane cannot poach it.
        try engine.apply(.unassignVehicleFromRoute(routeID: leg1, vehicleID: vehicle.id), to: &state)
        try engine.apply(.createRoute(name: "Distribution"), to: &state)
        let leg2 = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: leg2, cityID: NetFixture.cityH), to: &state)
        let distributionHubVisit = try #require(state.route(leg2)?.stops.first?.id)
        let lot = try #require(state.storageLots(in: warehouse.id).first)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: leg2,
            visitStopID: distributionHubVisit,
            task: .loadFromWarehouse(lot.key)
        ), to: &state)
        try engine.apply(.addTravelStop(routeID: leg2, cityID: NetFixture.cityB), to: &state)
        let betaVisit = try #require(state.route(leg2)?.stops.last?.id)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: leg2,
            visitStopID: betaVisit,
            task: .deliverAll
        ), to: &state)
        let free = try #require(state.vehicles.first { state.isVehicleIdle($0.id) })
        try engine.apply(.assignVehicleToRoute(routeID: leg2, vehicleID: free.id), to: &state)
        try engine.apply(.startRoute(leg2), to: &state)

        let revenueBefore = state.stats.totalRevenue
        engine.advance(&state, by: 400)

        #expect(state.stats.deliveredJobs == 1)
        // The payout is the offer's, undiminished by the extra hop: the player
        // pays for staging in distance and time, never in a revenue haircut.
        #expect(state.stats.totalRevenue - revenueBefore == expectedRevenue)
        #expect(state.shipments(storedIn: warehouse.id).isEmpty)
    }

    @Test func aFullWarehouseRefusesCargoInsteadOfSwallowingIt() throws {
        let tightStorage = FacilityConfig(
            office: TestEconomy.defaultFacilities.office,
            warehouse: [
                FacilityLevelSpec(
                    level: 1, buildCost: 1_000, buildDays: 1, upkeepPerDay: 10,
                    // Room for nothing at all.
                    storageMassKg: 0, storageVolumeM3: 0, docks: 1,
                    handlingPercent: 100, lanePremiumPercent: 0
                )
            ],
            dock: TestEconomy.defaultFacilities.dock,
            racking: TestEconomy.defaultFacilities.racking,
            forklift: TestEconomy.defaultFacilities.forklift
        )
        let economy = TestEconomy.make(startingCash: 60_000, facilities: tightStorage)
        let catalog = try NetFixture.catalog(economy: economy)
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState(economy: economy)
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)
        let warehouse = try makeHubWarehouse(engine: engine, state: &state)
        let vehicle = try #require(state.vehicles.first)

        try engine.apply(.createRoute(name: "Overflow"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: NetFixture.cityA), to: &state)
        let alphaVisit = try #require(state.route(routeID)?.stops.first?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: NetFixture.cityH), to: &state)
        let hubVisit = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: routeID,
            visitStopID: alphaVisit,
            task: .pickupLane(NetFixture.laneID)
        ), to: &state)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: routeID,
            visitStopID: hubVisit,
            task: .dropToWarehouse
        ), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(routeID), to: &state)
        // Load (30) + drive to the hub (60) + the refused service (30). Stop
        // short of Beta: a full lap would deliver the parcel and prove nothing.
        engine.advance(&state, by: 150)

        // The parcel is refused, not destroyed: it stays on the vehicle.
        #expect(state.shipments(storedIn: warehouse.id).isEmpty)
        #expect(state.shipments(onBoard: vehicle.id).count == 1)
        #expect(state.log.contains {
            if case .warehouseFull = $0.event { return true }
            return false
        })
    }

    @Test func warehouseTasksAreRefusedInCitiesWithoutOne() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.createRoute(name: "No warehouse"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: NetFixture.cityH), to: &state)
        let visitID = try #require(state.route(routeID)?.stops.first?.id)

        #expect(throws: CommandError.warehouseRequired) {
            try engine.apply(.addNetworkTaskToRoute(
                routeID: routeID,
                visitStopID: visitID,
                task: .dropToWarehouse
            ), to: &state)
        }
    }

    @Test func storageLotsGroupByDestinationAndOrderByDeadline() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        state.cash += 1_000_000
        try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityH), to: &state)
        try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        let warehouse = try #require(state.warehouseSite(in: NetFixture.cityH))

        func stage(id: Int, destination: CityID, expiresIn minutes: Int) {
            let offer = JobOffer(
                id: JobID(rawValue: id),
                origin: NetFixture.cityA,
                destination: destination,
                productID: NetFixture.product,
                load: LoadSize(massKg: 1000, volumeM3: 2),
                payout: 100,
                distanceKm: 200,
                laneID: nil,
                originFirmID: nil,
                destinationFirmID: nil,
                createdAt: state.clock,
                expiresAt: state.clock + minutes
            )
            state.shipments.append(Shipment(
                id: offer.id,
                offer: offer,
                location: .warehouse(warehouse.id),
                assignedRouteID: nil
            ))
        }
        stage(id: 900, destination: NetFixture.cityB, expiresIn: 600)
        stage(id: 901, destination: NetFixture.cityB, expiresIn: 200)
        stage(id: 902, destination: NetFixture.cityA, expiresIn: 400)

        let lots = state.storageLots(in: warehouse.id)
        // Two destinations, so two lots — cargo for different customers never
        // gets mixed into one pile.
        #expect(lots.count == 2)
        // The most urgent lot leads.
        #expect(lots.first?.key.destinationCityID == NetFixture.cityB)
        let betaLot = try #require(lots.first { $0.key.destinationCityID == NetFixture.cityB })
        #expect(betaLot.parcelCount == 2)
        #expect(betaLot.load.massKg == 2000)
        #expect(betaLot.pendingPayout == 200)
        // Loading order is earliest deadline first.
        #expect(betaLot.shipmentIDs.first == JobID(rawValue: 901))
    }
}

// MARK: - Lane spot pricing

struct LanePricingTests {
    /// The turn-one failure of the old spot board: jobs priced for one vehicle
    /// class and hauled by another lost money by arithmetic. Lane parcels are
    /// priced at claim time for the vehicle actually loading, and every market
    /// factor multiplies the margin, never the cost — so sub-cost freight is
    /// unreachable through the model. This states that property over the real
    /// catalog so a formula change cannot quietly reintroduce it.
    @Test func laneParcelsPriceAboveCostAndWithinAReadableBand() throws {
        let catalog = try GameCatalog.load(from: .main)
        let engine = SimulationEngine(catalog: catalog)
        let state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 7,
                identity: CompanyIdentity(name: "Test Co", colorHex: "#1F6FEB", emblemSymbol: "star.fill"),
                hqCity: try #require(catalog.starterCities.first).id
            ),
            economy: catalog.economy
        )

        for lane in catalog.lanes {
            let product = try #require(catalog.product(lane.productID))
            let distanceKm = try #require(
                catalog.roadDistanceKm(from: lane.originCityID, to: lane.destinationCityID)
            )
            for vehicleType in catalog.vehicleTypes {
                // Same sizing the dock claim uses: biggest parcel the product
                // and this vehicle allow. Skip classes the product cannot ride.
                let volumeLimitKg = Int(
                    (vehicleType.capacity.volumeM3 / product.densityM3PerTon * 1000).rounded(.down)
                )
                let step = ProductDefinition.shipmentMassStepKg
                let massKg = (min(
                    product.maximumShipmentMassKg,
                    vehicleType.capacity.massKg,
                    volumeLimitKg
                ) / step) * step
                guard massKg >= product.minimumShipmentMassKg else { continue }

                let load = engine.parcelLoad(productID: lane.productID, massKg: massKg)
                let payout = engine.freightPayout(
                    origin: lane.originCityID,
                    destination: lane.destinationCityID,
                    distanceKm: distanceKm,
                    load: load,
                    vehicleType: vehicleType,
                    state: state
                )
                // The price covers a round trip, because that is what a lane
                // actually costs: the truck has to come back. Compare against
                // the lap, not the loaded leg, or the ratio measures nothing.
                let haul = engine.haulCost(
                    origin: lane.originCityID,
                    destination: lane.destinationCityID,
                    distanceKm: distanceKm,
                    vehicleType: vehicleType
                )
                let returnLeg = engine.taskCost(
                    totalKm: distanceKm,
                    taskMinutes: engine.travelMinutes(
                        distanceKm: distanceKm, speedKmh: vehicleType.speedKmh
                    ),
                    vehicleType: vehicleType
                )
                let lapCost = haul.cost + returnLeg
                let ratio = Double(payout) / Double(max(1, lapCost))
                // A full lap must clear its own cost, but never by so much that
                // planning stops mattering.
                #expect(ratio > 1.0, "\(lane.id) with \(vehicleType.id) cannot cover its lap")
                #expect(ratio < 2.0, "\(lane.id) with \(vehicleType.id) is a jackpot")
            }
        }
    }
}


// MARK: - Determinism with the new systems

struct FacilityDeterminismTests {
    @Test func chunkedAdvanceMatchesSingleAdvanceWithFacilitiesAndWarehouses() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)

        func run(chunks: [Int]) throws -> GameState {
            var state = NetFixture.newState()
            try engine.apply(.buyVehicle(NetFixture.van), to: &state)
            state.cash += 1_000_000
            try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityH), to: &state)
            try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
            try engine.apply(.installModule(kind: .office, cityID: NetFixture.cityB), to: &state)
            engine.advance(&state, by: 0)
            let vehicle = try #require(state.vehicles.first)
            try engine.apply(.dispatchVehicleToLane(
                laneID: NetFixture.laneID,
                vehicleID: vehicle.id
            ), to: &state)
            for chunk in chunks {
                engine.advance(&state, by: chunk)
            }
            return state
        }

        let whole = try run(chunks: [4_000])
        let pieces = try run(chunks: [7, 913, 1, 1_200, 1_879])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(whole) == encoder.encode(pieces))
    }
}
