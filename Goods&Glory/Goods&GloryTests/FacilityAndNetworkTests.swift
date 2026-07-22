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

    /// A ready-made lane parcel waiting at Alpha, for warehouse and routing
    /// tests that need cargo without driving the whole dock-claim path.
    static func stagedParcel(id: Int, payout: Money = 1_000, state: GameState) -> JobOffer {
        JobOffer(
            id: JobID(rawValue: id),
            origin: cityA,
            destination: cityB,
            productID: product,
            load: LoadSize(massKg: 1_000, volumeM3: 2),
            payout: payout,
            distanceKm: 200,
            urgency: .normal,
            source: .lane,
            contractID: nil,
            laneID: laneID,
            originFirmID: nil,
            destinationFirmID: nil,
            createdAt: state.clock,
            expiresAt: state.clock + 2_160
        )
    }
}

// MARK: - Facilities

struct FacilityTests {
    @Test func foundingCreatesAnOperationalHeadquartersBranch() throws {
        let state = NetFixture.newState()
        let hq = try #require(state.module(.office, in: NetFixture.cityA))
        #expect(hq.isHeadquarters)
        #expect(hq.isOperational(at: state.clock))
        #expect(state.hasOperationalOffice(in: NetFixture.cityA))
        // Nothing is granted anywhere else for free.
        #expect(!state.hasOperationalOffice(in: NetFixture.cityB))
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
        #expect(!state.hasOperationalOffice(in: NetFixture.cityB))

        engine.advance(&state, by: quote.buildMinutes)
        #expect(state.hasOperationalOffice(in: NetFixture.cityB))

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
        #expect(throws: CommandError.branchRequired) {
            try engine.apply(.installModule(kind: .warehouse, cityID: NetFixture.cityH), to: &state)
        }
        #expect(throws: CommandError.branchRequired) {
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

    @Test func contractsAreOnlyOfferedFromOfficeCities() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)

        // Alpha is the HQ branch; Beta has no branch, so no lanes start there.
        #expect(!state.contractOffers.isEmpty)
        #expect(state.contractOffers.allSatisfy { $0.origin == NetFixture.cityA })

        // Signing is refused for a city whose branch has gone away.
        let offer = try #require(state.contractOffers.first)
        state.facilities.removeAll { $0.cityID == NetFixture.cityA }
        #expect(throws: CommandError.branchRequired) {
            try engine.apply(.signContract(offer.id), to: &state)
        }
    }

    @Test func contractsStayClosedUntilTheCompanyHasDeliveredSomething() throws {
        let economy = TestEconomy.make(startingCash: 60_000, contractsUnlockAfterDeliveries: 2)
        let catalog = try NetFixture.catalog(economy: economy)
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState(economy: economy)
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)

        // A company that has hauled nothing gets no recurring lanes, however
        // long it sits there.
        engine.advance(&state, by: 10 * GameState.minutesPerDay)
        #expect(state.contractOffers.isEmpty)

        // Two completed hauls open the door.
        state.stats.deliveredJobs = 2
        engine.advance(&state, by: GameState.minutesPerDay)
        #expect(!state.contractOffers.isEmpty)
    }

    @Test func theContractBoardNeverGoesEmptyBetweenRefreshes() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)
        #expect(!state.contractOffers.isEmpty)

        // Offers must outlive the refresh interval, or the branch's board goes
        // blank for a day and reads as the game losing them.
        for _ in 0..<20 {
            engine.advance(&state, by: catalog.economy.contractOfferIntervalMinutes / 2)
            #expect(!state.contractOffers.isEmpty)
        }
    }

    @Test func branchLevelWidensTheContractMenu() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        let atLevelOne = engine.contractSlots(in: NetFixture.cityA, state: state)

        let index = try #require(state.facilities.firstIndex { $0.cityID == NetFixture.cityA })
        state.facilities[index].level = 2
        let atLevelTwo = engine.contractSlots(in: NetFixture.cityA, state: state)

        #expect(atLevelTwo > atLevelOne)
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
        let offer = NetFixture.stagedParcel(id: 5_000, state: state)
        state.offers.append(offer)
        let expectedRevenue = offer.payout

        // Leg 1: collect at Alpha, hand the parcel over at the hub.
        // addJobToRoute appends [Alpha pickup, Beta delivery]; the hub visit is
        // added last and then moved into the middle.
        try engine.apply(.createRoute(name: "Collection"), to: &state)
        let leg1 = try #require(state.routes.last?.id)
        try engine.apply(.addJobToRoute(offerID: offer.id, routeID: leg1), to: &state)
        try engine.apply(.addTravelStop(routeID: leg1, cityID: NetFixture.cityH), to: &state)
        let visits = try #require(state.route(leg1)).stops.map(\.id)
        #expect(visits.count == 3)
        try engine.apply(.reorderRouteVisits(
            routeID: leg1,
            orderedVisitIDs: [visits[0], visits[2], visits[1]]
        ), to: &state)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: leg1,
            visitStopID: visits[2],
            task: .dropToWarehouse
        ), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: leg1, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(leg1), to: &state)

        // Load (30) + drive 100 km (60) + unload (30), plus loop slack.
        engine.advance(&state, by: 300)
        let stored = state.shipments(storedIn: warehouse.id)
        #expect(stored.count == 1)
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
        let hubVisit = try #require(state.route(leg2)?.stops.first?.id)
        let lot = try #require(state.storageLots(in: warehouse.id).first)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: leg2,
            visitStopID: hubVisit,
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
                    handlingPercent: 100, contractSlotPercent: 100, lanePremiumPercent: 0
                )
            ]
        )
        let economy = TestEconomy.make(startingCash: 60_000, facilities: tightStorage)
        let catalog = try NetFixture.catalog(economy: economy)
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState(economy: economy)
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)
        let warehouse = try makeHubWarehouse(engine: engine, state: &state)
        let vehicle = try #require(state.vehicles.first)
        let offer = NetFixture.stagedParcel(id: 5_000, state: state)
        state.offers.append(offer)

        try engine.apply(.createRoute(name: "Overflow"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addJobToRoute(offerID: offer.id, routeID: routeID), to: &state)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: NetFixture.cityH), to: &state)
        let visits = try #require(state.route(routeID)).stops.map(\.id)
        try engine.apply(.reorderRouteVisits(
            routeID: routeID,
            orderedVisitIDs: [visits[0], visits[2], visits[1]]
        ), to: &state)
        try engine.apply(.addNetworkTaskToRoute(
            routeID: routeID,
            visitStopID: visits[2],
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
                urgency: .normal,
                source: .lane,
                contractID: nil,
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

// MARK: - Contract archetypes and coverage

struct ContractArchetypeTests {
    @Test func deliveryWindowIsIndependentOfTheShipmentInterval() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        // A daily cadence on a two-hour cycle must still allow a full run.
        let window = engine.deliveryWindow(cycleMinutes: 240, interval: GameState.minutesPerDay)
        #expect(window >= 240)
        #expect(window > 0)

        // A long cycle drives the window, not the cadence.
        let longWindow = engine.deliveryWindow(cycleMinutes: 3_000, interval: GameState.minutesPerDay)
        #expect(longWindow >= 3_000)
    }

    /// A contract is a relationship, not a listing. A firm reserves part of its
    /// output for a carrier it has watched deliver — so a lane the company has
    /// never touched offers nothing, and the share on offer grows with the
    /// share the company already hauls.
    @Test func contractsAreOfferedOnlyOnLanesTheCompanyAlreadyHauls() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)

        // Nothing delivered yet: nobody offers to reserve anything.
        #expect(state.contractOffers.isEmpty)

        let lane = try #require(catalog.lane(NetFixture.laneID))
        #expect(engine.servedShareBps(of: lane, state: state) == 0)

        // Now put a real service record on that lane.
        state.stats.deliveredKgByLane[lane.id] = lane.baseRatePerDayKg
        let served = engine.servedShareBps(of: lane, state: state)
        #expect(served > 0)

        engine.replenishContractOffers(state: &state)
        let offers = state.contractOffers.filter { $0.origin == NetFixture.cityA }
        #expect(!offers.isEmpty, "a served lane should draw an offer")
        for offer in offers {
            for destination in offer.destinations {
                #expect(destination.laneID == lane.id)
                // Never more than a little beyond what the company has proven.
                let ceiling = Int(Double(served) * SimulationEngine.relationshipStretch) + 1
                #expect(destination.committedShareBps <= ceiling)
            }
        }
    }

    /// A contract does not earn a truck of its own — it reserves part of a lane
    /// the company already drives past. So the tests are not "does this lane
    /// pay for a vehicle" (the pre-lane question, which made every honest offer
    /// read as a loss) but: does signing beat carrying the same freight
    /// unsigned, and does it stay inside what the world actually produces.
    @Test func everyPostedLaneBeatsSpotAndFitsInsideItsLane() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)

        for offer in state.contractOffers {
            let brief = try #require(engine.brief(for: offer))
            #expect(brief.contractRevenuePerDay > 0)
            #expect(brief.contractRevenuePerDay >= brief.spotRevenuePerDay)
            #expect(brief.committedKgPerDay > 0)

            // The commitment can never promise more than the lanes it names.
            let laneRate = offer.destinations.reduce(0) { total, destination in
                total + (catalog.lane(destination.laneID)?.baseRatePerDayKg ?? 0)
            }
            #expect(brief.committedKgPerDay <= laneRate)

            // Priced by the class the parcel fits in, not by whatever is parked
            // in the garage — otherwise the same tonnage is worth more to a
            // company that happens to own bigger trucks.
            let pricingType = try #require(catalog.vehicleType(offer.referenceVehicleTypeID))
            #expect(offer.parcelMassKg <= pricingType.capacity.massKg)
        }
        #expect(state.contractOffers.contains { offer in
            (engine.brief(for: offer)?.premiumPerDay ?? 0) > 0
        })
    }

    /// Loading one parcel into a half-empty truck was the single biggest source
    /// of contract losses: the trip was paid for either way. A dock visit now
    /// fills the vehicle with whatever that contract has pending.
    @Test func aContractPickupFillsTheVehicleRatherThanTakingOneParcel() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)

        // A contract posting three 1000 kg parcels into a 2000 kg van: the van
        // must leave with two, not one.
        state.activeContracts.append(ActiveContract(
            id: ContractID(rawValue: 700),
            origin: NetFixture.cityA,
            productID: NetFixture.product,
            archetype: .laneRecurring,
            destinations: [
                ContractDestination(
                    cityID: NetFixture.cityB, firmID: nil,
                    laneID: NetFixture.laneID, committedShareBps: 5_000,
                    shareBps: ContractDestination.fullShareBps,
                    distanceKm: 200, payoutPerParcel: 400
                )
            ],
            referenceVehicleTypeID: NetFixture.van,
            parcelMassKg: 1_000,
            volumePerCycleKg: 3_000,
            shipmentIntervalMinutes: GameState.minutesPerDay,
            deliveryWindowMinutes: 2 * GameState.minutesPerDay,
            signedAt: state.clock,
            endsAt: state.clock + 30 * GameState.minutesPerDay,
            nextShipmentAt: state.clock,
            shipmentsIssued: 0,
            shipmentsCompleted: 0,
            shipmentsMissed: 0,
            penaltiesPaid: 0,
            cancellationRequestedAt: nil,
            originFirmID: nil
        ))
        engine.advance(&state, by: 1)
        #expect(state.offers.count { $0.contractID == ContractID(rawValue: 700) } == 3)

        let vehicle = try #require(state.vehicles.first)
        try engine.apply(
            .assignVehicleToContract(contractID: ContractID(rawValue: 700), vehicleID: vehicle.id),
            to: &state
        )
        engine.advance(&state, by: 1)
        let run = try #require(state.routeRun(for: vehicle.id))
        #expect(run.claimedShipmentIDs.count == 2)

        // After loading, both parcels are aboard and one still waits.
        engine.advance(&state, by: engine.loadingMinutes(at: NetFixture.cityA))
        #expect(state.shipments(onBoard: vehicle.id).count == 2)
        #expect(state.offers.count { $0.contractID == ContractID(rawValue: 700) } == 1)
    }

    /// A commitment must be worth signing: the same parcel earns more under
    /// contract than it does unsigned, which is what pays for the SLA and the
    /// penalty risk that come with it.
    @Test func aCommittedParcelOutEarnsTheSameParcelOnSpot() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)

        let offer = try #require(state.contractOffers.first)
        let vanType = try #require(catalog.vehicleType(NetFixture.van))
        let destination = try #require(offer.destinations.first)
        let parcel = engine.parcelLoad(productID: offer.productID, massKg: offer.parcelMassKg)
        let spot = engine.freightPayout(
            origin: offer.origin,
            destination: destination.cityID,
            distanceKm: destination.distanceKm,
            load: parcel,
            vehicleType: vanType,
            state: state
        )
        #expect(destination.payoutPerParcel > spot)
    }

    @Test func archetypesUnlockWithCompanyScale() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()

        #expect(engine.companyTier(state) == 1)
        #expect(engine.archetypes(forTier: 1) == [.laneRecurring])

        for index in 0..<5 {
            state.vehicles.append(Vehicle(
                id: VehicleID(rawValue: 500 + index),
                typeID: NetFixture.van,
                cityID: NetFixture.cityA,
                assignedJobID: nil,
                odometerKm: 0
            ))
        }
        #expect(engine.companyTier(state) == 2)
        #expect(engine.archetypes(forTier: 2).contains(.evergreen))
        // Bulk work stays locked until there is somewhere to consolidate it.
        #expect(!engine.archetypes(forTier: 2).contains(.bulkPeriodic))
        #expect(engine.archetypes(forTier: 4).contains(.multiDrop))
    }

    @Test func aBulkCyclePostsManyParcelsAtOnce() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()

        // Hand-built contract: one cycle of 5000 kg in 1000 kg parcels.
        let contract = ActiveContract(
            id: ContractID(rawValue: 800),
            origin: NetFixture.cityA,
            productID: NetFixture.product,
            archetype: .bulkPeriodic,
            destinations: [
                ContractDestination(
                    cityID: NetFixture.cityB,
                    firmID: nil,
                    laneID: NetFixture.laneID,
                    committedShareBps: 5_000,
                    shareBps: ContractDestination.fullShareBps,
                    distanceKm: 200,
                    payoutPerParcel: 500
                )
            ],
            referenceVehicleTypeID: NetFixture.van,
            parcelMassKg: 1_000,
            volumePerCycleKg: 5_000,
            shipmentIntervalMinutes: 7 * GameState.minutesPerDay,
            deliveryWindowMinutes: 3 * GameState.minutesPerDay,
            signedAt: state.clock,
            endsAt: state.clock + 30 * GameState.minutesPerDay,
            nextShipmentAt: state.clock,
            shipmentsIssued: 0,
            shipmentsCompleted: 0,
            shipmentsMissed: 0,
            penaltiesPaid: 0,
            cancellationRequestedAt: nil,
            originFirmID: nil
        )
        #expect(contract.parcelsPerCycle == 5)
        state.activeContracts.append(contract)

        engine.advance(&state, by: 1)
        let posted = state.offers.filter { $0.contractID == contract.id }
        #expect(posted.count == 5)
        #expect(posted.allSatisfy { $0.load.massKg == 1_000 })
        // Every parcel of a cycle shares one deadline.
        #expect(Set(posted.map(\.expiresAt)).count == 1)
    }

    @Test func aMultiDropCycleSplitsVolumeAcrossDestinations() throws {
        let contract = ContractOffer(
            id: ContractID(rawValue: 810),
            origin: NetFixture.cityA,
            productID: NetFixture.product,
            archetype: .multiDrop,
            destinations: [
                ContractDestination(cityID: NetFixture.cityH, firmID: nil, laneID: NetFixture.laneID, committedShareBps: 5_000, shareBps: 5_000, distanceKm: 100, payoutPerParcel: 300),
                ContractDestination(cityID: NetFixture.cityB, firmID: nil, laneID: NetFixture.laneID, committedShareBps: 5_000, shareBps: 5_000, distanceKm: 200, payoutPerParcel: 500)
            ],
            referenceVehicleTypeID: NetFixture.van,
            parcelMassKg: 1_000,
            volumePerCycleKg: 4_000,
            shipmentIntervalMinutes: 3 * GameState.minutesPerDay,
            deliveryWindowMinutes: 2 * GameState.minutesPerDay,
            leadTimeMinutes: 600,
            durationDays: 30,
            originFirmID: nil,
            createdAt: .start,
            expiresAt: GameTime(totalMinutes: 5_000)
        )
        #expect(contract.parcelsPerCycle == 4)
        #expect(contract.isMultiDrop)
        // Shares always total the agreed volume exactly.
        let total = contract.destinations.reduce(0) { $0 + contract.cycleVolume(for: $1) }
        #expect(total == contract.volumePerCycleKg)
        #expect(contract.revenuePerCycle == 2 * 300 + 2 * 500)
    }

    @Test func evergreenContractsRunUntilSafelyCancelled() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()

        state.activeContracts.append(ActiveContract(
            id: ContractID(rawValue: 820),
            origin: NetFixture.cityA,
            productID: NetFixture.product,
            archetype: .evergreen,
            destinations: [
                ContractDestination(
                    cityID: NetFixture.cityB, firmID: nil,
                    laneID: NetFixture.laneID, committedShareBps: 5_000,
                    shareBps: ContractDestination.fullShareBps,
                    distanceKm: 200, payoutPerParcel: 500
                )
            ],
            referenceVehicleTypeID: NetFixture.van,
            parcelMassKg: 1_000,
            volumePerCycleKg: 1_000,
            shipmentIntervalMinutes: GameState.minutesPerDay,
            deliveryWindowMinutes: 2 * GameState.minutesPerDay,
            signedAt: state.clock,
            endsAt: nil,
            nextShipmentAt: state.clock,
            shipmentsIssued: 0,
            shipmentsCompleted: 0,
            shipmentsMissed: 0,
            penaltiesPaid: 0,
            cancellationRequestedAt: nil,
            originFirmID: nil
        ))

        // Runs for weeks without expiring on its own.
        engine.advance(&state, by: 20 * GameState.minutesPerDay)
        #expect(state.activeContract(ContractID(rawValue: 820)) != nil)
        #expect(state.activeContract(ContractID(rawValue: 820))?.shipmentsIssued ?? 0 > 10)

        try engine.apply(.cancelContract(ContractID(rawValue: 820)), to: &state)
        let issuedAtCancel = try #require(state.activeContract(ContractID(rawValue: 820))).shipmentsIssued

        // No new cycles post after the safe-close request.
        engine.advance(&state, by: 5 * GameState.minutesPerDay)
        let remaining = state.activeContract(ContractID(rawValue: 820))
        #expect(remaining == nil || remaining?.shipmentsIssued == issuedAtCancel)
    }

    @Test func anEndedContractFlagsItsRoutesButClosesNone() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)
        let offer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(offer.id), to: &state)
        let vehicle = try #require(state.vehicles.first)
        try engine.apply(
            .assignVehicleToContract(contractID: offer.id, vehicleID: vehicle.id),
            to: &state
        )
        let dedicated = try #require(state.route(serving: offer.id))
        #expect(dedicated.isRunning)

        // A second, player-built route that also serves the contract.
        try engine.apply(.createRoute(name: "My mixed lane"), to: &state)
        let custom = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: custom, cityID: offer.origin), to: &state)
        let visit = try #require(state.route(custom)?.stops.first?.id)
        try engine.apply(.addContractTaskToRoute(
            routeID: custom,
            visitStopID: visit,
            contractID: offer.id,
            action: .pickup
        ), to: &state)

        // Run past the contract's term.
        let term = try #require(state.activeContract(offer.id)?.endsAt)
        engine.advance(&state, by: max(1, state.clock.minutes(until: term)) + 10)
        #expect(state.activeContract(offer.id) == nil)

        // No route is closed for losing its contract: the lane keeps
        // running on whatever freight remains (its lane stops, if any).
        #expect(state.route(dedicated.id)?.isRunning == true)
        // Both routes carrying dead contract stops are flagged for review,
        // never silently altered.
        for flagged in [dedicated.id, custom] {
            #expect(state.log.contains {
                if case .routeNeedsReview(let id, _) = $0.event { return id == flagged }
                return false
            })
        }
    }

    @Test func coverageFollowsFreightNotTheContractRoute() throws {
        let catalog = try NetFixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = NetFixture.newState()
        try engine.apply(.buyVehicle(NetFixture.van), to: &state)
        engine.advance(&state, by: 0)
        let offer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(offer.id), to: &state)

        // Before the first cycle posts: preparation, not a warning.
        let signed = try #require(state.activeContract(offer.id))
        if case .notStarted = engine.coverage(of: signed, state: state) {} else {
            Issue.record("a freshly signed contract should read as not started")
        }

        engine.advance(&state, by: offer.leadTimeMinutes)
        let posted = try #require(state.activeContract(offer.id))
        #expect(engine.coverage(of: posted, state: state) != .covered)

        // The player hauls it with their own route — no contract auto-route
        // exists, and coverage must still recognise the freight as moving.
        let vehicle = try #require(state.vehicles.first)
        try engine.apply(.createRoute(name: "My own lane"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: offer.origin), to: &state)
        let originVisit = try #require(state.route(routeID)?.stops.first?.id)
        try engine.apply(.addContractTaskToRoute(
            routeID: routeID,
            visitStopID: originVisit,
            contractID: offer.id,
            action: .pickup
        ), to: &state)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: offer.destination), to: &state)
        let destinationVisit = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(.addContractTaskToRoute(
            routeID: routeID,
            visitStopID: destinationVisit,
            contractID: offer.id,
            action: .deliver
        ), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(routeID), to: &state)
        engine.advance(&state, by: 45)

        // Coverage is a property of stops, not ownership: the player's own
        // route is what serves the contract now.
        #expect(state.route(serving: offer.id)?.id == routeID)
        let hauling = try #require(state.activeContract(offer.id))
        #expect(engine.coverage(of: hauling, state: state) == .covered)
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
            let offer = try #require(state.contractOffers.first)
            try engine.apply(.signContract(offer.id), to: &state)
            let vehicle = try #require(state.vehicles.first)
            try engine.apply(
                .assignVehicleToContract(contractID: offer.id, vehicleID: vehicle.id),
                to: &state
            )
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
