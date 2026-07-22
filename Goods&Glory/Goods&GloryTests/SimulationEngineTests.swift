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

    /// A hand-built lane parcel offer, for tests that exercise the legacy
    /// accept/route paths without going through the dock claim.
    static func laneOffer(
        id: Int,
        massKg: Int = 1000,
        payout: Money = 1000,
        state: GameState
    ) -> JobOffer {
        JobOffer(
            id: JobID(rawValue: id),
            origin: cityA,
            destination: cityB,
            productID: product,
            load: LoadSize(massKg: massKg, volumeM3: Double(massKg) / 1000 * 2),
            payout: payout,
            distanceKm: 100,
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
        #expect(route.stops.map(\.task).contains(.deliverAll))

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
        #expect(shipment.offer.source == .lane)
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
            urgency: .normal,
            source: .lane,
            contractID: nil,
            laneID: Fixture.laneID,
            originFirmID: nil,
            destinationFirmID: nil,
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

    @Test func signingContractPostsDiscountedShipments() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        #expect(!state.contractOffers.isEmpty)
        let contractOffer = try #require(state.contractOffers.first)
        let openBefore = state.contractOffers.count
        try engine.apply(.signContract(contractOffer.id), to: &state)
        #expect(state.activeContracts.contains { $0.id == contractOffer.id })
        #expect(state.contractOffers.count == openBefore - 1)
        #expect(state.contractOffers.allSatisfy { $0.id != contractOffer.id })

        // Lead time: signing buys preparation, not an instant obligation.
        #expect(!state.offers.contains { $0.source == .contract && $0.contractID == contractOffer.id })
        let signed = try #require(state.activeContract(contractOffer.id))
        #expect(signed.nextShipmentAt == state.clock + contractOffer.leadTimeMinutes)

        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        #expect(state.offers.contains { $0.source == .contract && $0.contractID == contractOffer.id })

        let shipment = try #require(state.offers.first { $0.source == .contract })
        #expect(shipment.payout == contractOffer.payoutPerShipment)
        // The delivery window is its own term, not the shipment interval: a
        // daily lane over a long leg must still be physically deliverable.
        #expect(shipment.expiresAt == shipment.createdAt + contractOffer.deliveryWindowMinutes)

        // Round-trip cost-plus pricing: above the cycle cost, below spot-normal.
        let vanType = try #require(catalog.vehicleType(Fixture.van))
        let cycleMinutes = engine.contractCycleMinutes(
            origin: contractOffer.origin,
            destination: contractOffer.destination,
            distanceKm: contractOffer.distanceKm,
            vehicleType: vanType
        )
        let cycleCost = engine.taskCost(
            totalKm: contractOffer.distanceKm * 2,
            taskMinutes: cycleMinutes,
            vehicleType: vanType
        )
        #expect(shipment.payout > cycleCost)
        // Note: a contract parcel prices the *round trip* (the lane commits the
        // vehicle to come back for the next cycle) while a spot parcel prices
        // the loaded leg only, so the two are not directly comparable here.
        // Phase 3 replaces this with the real relation — a contract pays the
        // lane's spot rate plus a commitment premium — and tests it there.
    }

    @Test func assignedVehicleRunsContractCycleAndReturns() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let vehicle = try #require(state.vehicles.first)
        try engine.apply(
            .assignVehicleToContract(contractID: contractOffer.id, vehicleID: vehicle.id),
            to: &state
        )

        // Assignment created a running lane: the contract dock first, then the
        // same-lane pickup so the truck leaves full, then one catch-all delivery.
        let route = try #require(state.route(serving: contractOffer.id))
        #expect(route.vehicleIDs == [vehicle.id])
        #expect(route.isRunning)
        #expect(route.stops.first?.task == .pickupContract(contractOffer.id))
        #expect(route.stops.last?.task == .deliverAll)
        #expect(route.coveredLaneIDs == [Fixture.laneID])
        #expect(route.stops.map(\.cityID) == [
            contractOffer.origin, contractOffer.origin, contractOffer.destination
        ])
        #expect(state.routeRun(for: vehicle.id) != nil)

        // A double vehicle assignment to any route is rejected.
        #expect(throws: CommandError.vehicleAlreadyAssigned) {
            try engine.apply(
                .assignVehicleToContract(contractID: contractOffer.id, vehicleID: vehicle.id),
                to: &state
            )
        }

        // After enough time for a full lap the shipment is delivered and the
        // vehicle loops back to wait at the pickup stop.
        engine.advance(&state, by: 2_000)
        let contract = try #require(state.activeContract(contractOffer.id))
        #expect(contract.shipmentsCompleted >= 1)
        #expect(contract.shipmentsMissed == 0)
        let served = try #require(state.vehicles.first)
        #expect(served.cityID == contractOffer.origin)
        let run = try #require(state.routeRun(for: vehicle.id))
        #expect(run.phase == .waiting)
    }

    @Test func waitingContractRouteWakesAndLoadsTheNextShipment() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let vehicle = try #require(state.vehicles.first)
        let vehicleType = try #require(catalog.vehicleType(vehicle.typeID))
        try engine.apply(
            .assignVehicleToContract(contractID: contractOffer.id, vehicleID: vehicle.id),
            to: &state
        )

        let firstLapMinutes = engine.contractCycleMinutes(
            origin: contractOffer.origin,
            destination: contractOffer.destination,
            distanceKm: contractOffer.distanceKm,
            vehicleType: vehicleType
        )
        engine.advance(&state, by: firstLapMinutes)

        let waiting = try #require(state.routeRun(for: vehicle.id))
        #expect(waiting.phase == .waiting)
        #expect(waiting.stopIndex == 0)
        let wakeAt = try #require(state.activeContract(contractOffer.id)).nextShipmentAt
        #expect(state.clock < wakeAt)
        #expect(waiting.phaseEndsAt > wakeAt)

        engine.advance(&state, by: state.clock.minutes(until: wakeAt))

        let servicing = try #require(state.routeRun(for: vehicle.id))
        #expect(servicing.id == waiting.id)
        #expect(servicing.phase == .servicing)
        #expect(servicing.stopIndex == 0)
        #expect(servicing.phaseStartedAt == wakeAt)
        let claimedID = try #require(servicing.claimedShipmentIDs.first)
        let claimed = try #require(state.shipment(claimedID))
        #expect(claimed.loadedVehicleID == nil)
        #expect(state.offers.allSatisfy { $0.id != claimedID })

        engine.advance(&state, by: engine.loadingMinutes(at: contractOffer.origin))

        let loaded = try #require(state.shipment(claimedID))
        #expect(loaded.loadedVehicleID == vehicle.id)
        // The lap moved past the contract dock. Whether it is topping up at
        // the lane dock or already driving, it must not be parked: a loaded
        // vehicle never waits.
        let moving = try #require(state.routeRun(for: vehicle.id))
        #expect(moving.stopIndex > 0)
        #expect(moving.phase != .waiting)
    }

    @Test func customRouteExecutesRecurringContractTasks() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        try engine.apply(.createRoute(name: "Recurring lane"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.origin), to: &state)
        let originVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.destination), to: &state)
        let destinationVisitID = try #require(state.route(routeID)?.stops.last?.id)

        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: originVisitID,
                contractID: contractOffer.id,
                action: .pickup
            ),
            to: &state
        )
        // Adding the exact recurring action again is idempotent.
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: originVisitID,
                contractID: contractOffer.id,
                action: .pickup
            ),
            to: &state
        )
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: destinationVisitID,
                contractID: contractOffer.id,
                action: .deliver
            ),
            to: &state
        )

        let configured = try #require(state.route(routeID))
        #expect(configured.stops.filter { $0.task == .pickupContract(contractOffer.id) }.count == 1)
        #expect(configured.stops.map(\.task) == [
            .travel,
            .pickupContract(contractOffer.id),
            .travel,
            .deliverContract(contractOffer.id)
        ])

        let vehicle = try #require(state.vehicles.first)
        try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(routeID), to: &state)
        engine.advance(&state, by: 2_000)

        let contract = try #require(state.activeContract(contractOffer.id))
        #expect(contract.shipmentsCompleted >= 1)
        #expect(state.routeRun(for: vehicle.id) != nil)
    }

    @Test func routeCannotStartWithoutAnAssignedVehicleOrWithIncompleteContractTasks() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        try engine.apply(.createRoute(name: "Draft"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: Fixture.cityA), to: &state)
        #expect(throws: CommandError.noVehicleAssigned) {
            try engine.apply(.startRoute(routeID), to: &state)
        }
        #expect(state.route(routeID)?.isRunning == false)

        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)
        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let visitID = try #require(state.route(routeID)?.stops.first?.id)
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: visitID,
                contractID: contractOffer.id,
                action: .pickup
            ),
            to: &state
        )
        try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id), to: &state)
        #expect(throws: CommandError.incompleteRouteTasks) {
            try engine.apply(.startRoute(routeID), to: &state)
        }
        #expect(state.route(routeID)?.isRunning == false)
    }

    @Test func routeVisitReorderMovesEachCityAndItsTasksAtomically() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        try engine.apply(.createRoute(name: "Reorder"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.origin), to: &state)
        let originVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.destination), to: &state)
        let destinationVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: originVisitID,
                contractID: contractOffer.id,
                action: .pickup
            ),
            to: &state
        )
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: destinationVisitID,
                contractID: contractOffer.id,
                action: .deliver
            ),
            to: &state
        )

        try engine.apply(
            .reorderRouteVisits(
                routeID: routeID,
                orderedVisitIDs: [destinationVisitID, originVisitID]
            ),
            to: &state
        )

        let reordered = try #require(state.route(routeID))
        #expect(reordered.stops.map(\.cityID) == [
            contractOffer.destination,
            contractOffer.destination,
            contractOffer.origin,
            contractOffer.origin
        ])
        #expect(reordered.stops.map(\.task) == [
            .travel,
            .deliverContract(contractOffer.id),
            .travel,
            .pickupContract(contractOffer.id)
        ])
    }

    @Test func removingRouteVisitRemovesItsLocalContractTasks() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        try engine.apply(.createRoute(name: "Trim"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.origin), to: &state)
        let originVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.destination), to: &state)
        let destinationVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: originVisitID,
                contractID: contractOffer.id,
                action: .pickup
            ),
            to: &state
        )
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: destinationVisitID,
                contractID: contractOffer.id,
                action: .deliver
            ),
            to: &state
        )

        try engine.apply(
            .removeRouteVisit(routeID: routeID, visitStopID: originVisitID),
            to: &state
        )

        let trimmed = try #require(state.route(routeID))
        #expect(trimmed.stops.map(\.cityID) == [contractOffer.destination, contractOffer.destination])
        #expect(trimmed.stops.map(\.task) == [
            .travel,
            .deliverContract(contractOffer.id)
        ])
    }

    @Test func removingRouteVisitDetachesLegacyShipmentPairAtomically() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let shipment = try #require(state.offers.first {
            $0.source == .contract && $0.contractID == contractOffer.id
        })
        try engine.apply(.createRoute(name: "Legacy shipment"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addJobToRoute(offerID: shipment.id, routeID: routeID), to: &state)
        let pickupVisitID = try #require(state.route(routeID)?.stops.first?.id)

        try engine.apply(
            .removeRouteVisit(routeID: routeID, visitStopID: pickupVisitID),
            to: &state
        )

        #expect(state.route(routeID)?.stops.isEmpty == true)
        #expect(state.shipment(shipment.id) == nil)
        #expect(state.offers.contains { $0.id == shipment.id })
    }

    @Test func deletingRunningRouteFinishesLoadedCargoThenReleasesAndPurges() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        try engine.apply(.createRoute(name: "Cancelable"), to: &state)
        let routeID = try #require(state.routes.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.origin), to: &state)
        let originVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(.addTravelStop(routeID: routeID, cityID: contractOffer.destination), to: &state)
        let destinationVisitID = try #require(state.route(routeID)?.stops.last?.id)
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: originVisitID,
                contractID: contractOffer.id,
                action: .pickup
            ),
            to: &state
        )
        try engine.apply(
            .addContractTaskToRoute(
                routeID: routeID,
                visitStopID: destinationVisitID,
                contractID: contractOffer.id,
                action: .deliver
            ),
            to: &state
        )
        let vehicle = try #require(state.vehicles.first)
        try engine.apply(.assignVehicleToRoute(routeID: routeID, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(routeID), to: &state)

        engine.advance(&state, by: 0)
        engine.advance(&state, by: engine.loadingMinutes(at: contractOffer.origin))
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
        #expect(state.vehicle(vehicle.id)?.cityID == contractOffer.destination)
        #expect(state.isVehicleIdle(vehicle.id))
        // A dock visit fills the vehicle rather than taking one box, so the
        // wind-down may legitimately finish more than a single parcel.
        #expect((state.activeContract(contractOffer.id)?.shipmentsCompleted ?? 0) >= 1)
    }

    @Test func customRouteCarriesAnAcceptedJobAroundTheLoop() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)
        let offer = Fixture.laneOffer(id: 999, state: state)
        state.offers.append(offer)

        try engine.apply(.createRoute(name: "Loop"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: offer.id, routeID: route.id), to: &state)
        try engine.apply(.addTravelStop(routeID: route.id, cityID: Fixture.cityA), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: route.id, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(route.id), to: &state)
        #expect(state.shipments.count == 1)
        #expect(state.routeRun(for: vehicle.id) != nil)

        // Lap: load (30) + drive (60) + unload (30) + empty return (60).
        engine.advance(&state, by: 200)
        #expect(state.shipments.isEmpty)
        #expect(state.stats.deliveredJobs == 1)
        #expect(state.stats.totalRevenue > 0)

        // Vehicle keeps looping: it returns to the travel stop in city A.
        let served = try #require(state.vehicles.first)
        #expect(served.cityID == Fixture.cityA)

        // Stopping releases the vehicle once it is empty.
        try engine.apply(.stopRoute(route.id), to: &state)
        engine.advance(&state, by: 300)
        #expect(state.routeRun(for: vehicle.id) == nil)
        #expect(state.isVehicleIdle(vehicle.id))
    }

    @Test func routeLogsAShipmentSkippedForInsufficientCapacity() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        let vehicle = try #require(state.vehicles.first)
        let oversized = JobOffer(
            id: JobID(rawValue: 999),
            origin: Fixture.cityA,
            destination: Fixture.cityB,
            productID: Fixture.product,
            load: LoadSize(massKg: 5_000, volumeM3: 5),
            payout: 1_000,
            distanceKm: 100,
            urgency: .normal,
            source: .lane,
            contractID: nil,
            laneID: Fixture.laneID,
            originFirmID: nil,
            destinationFirmID: nil,
            createdAt: state.clock,
            expiresAt: state.clock + 720
        )
        state.offers.append(oversized)

        try engine.apply(.createRoute(name: "Oversized"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: oversized.id, routeID: route.id), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: route.id, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(route.id), to: &state)

        engine.advance(&state, by: 1)

        let shipment = try #require(state.shipment(oversized.id))
        #expect(shipment.loadedVehicleID == nil)
        let run = try #require(state.routeRun(for: vehicle.id))
        #expect(run.phase == .traveling)
        #expect(run.stopIndex == 1)
        let skipLogs = state.log.filter { entry in
            if case let .routeShipmentSkipped(loggedRouteID, loggedJobID) = entry.event {
                return loggedRouteID == route.id && loggedJobID == oversized.id
            }
            return false
        }
        #expect(skipLogs.count == 1)
    }

    @Test func twoRouteVehiclesCannotClaimTheSameLaneShipment() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        try engine.apply(.buyVehicle(Fixture.van), to: &state)

        let vehicles = state.vehicles
        #expect(vehicles.count == 2)
        let offer = Fixture.laneOffer(id: 999, state: state)
        state.offers.append(offer)
        try engine.apply(.createRoute(name: "Shared"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: offer.id, routeID: route.id), to: &state)
        for vehicle in vehicles {
            try engine.apply(.assignVehicleToRoute(routeID: route.id, vehicleID: vehicle.id), to: &state)
        }
        try engine.apply(.startRoute(route.id), to: &state)

        engine.advance(&state, by: 1)

        let claimers = state.routeRuns.filter { $0.claimedShipmentIDs.contains(offer.id) }
        #expect(claimers.count == 1)
        let claimer = try #require(claimers.first)
        #expect(claimer.phase == .servicing)
        let other = try #require(state.routeRuns.first { $0.id != claimer.id })
        #expect(other.phase == .traveling)
        #expect(other.stopIndex == 1)

        engine.advance(&state, by: engine.loadingMinutes(at: offer.origin))

        let shipment = try #require(state.shipment(offer.id))
        #expect(shipment.loadedVehicleID == claimer.vehicleID)
        let pickupLogs = state.log.filter { entry in
            if case let .jobPickedUp(jobID, _, _) = entry.event {
                return jobID == offer.id
            }
            return false
        }
        #expect(pickupLogs.count == 1)
    }

    @Test func removingContractRouteJobBeforeExpiryReturnsItsOriginalDeadline() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let accepted = try #require(state.offers.first {
            $0.source == .contract && $0.contractID == contractOffer.id
        })
        try engine.apply(.createRoute(name: "Contract overflow"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: accepted.id, routeID: route.id), to: &state)

        try engine.apply(.removeJobFromRoute(jobID: accepted.id, routeID: route.id), to: &state)

        #expect(state.shipment(accepted.id) == nil)
        let editedRoute = try #require(state.route(route.id))
        #expect(editedRoute.stops.allSatisfy {
            $0.task != .pickupShipment(accepted.id) && $0.task != .deliverShipment(accepted.id)
        })
        let returned = try #require(state.offers.first { $0.id == accepted.id })
        #expect(returned.source == .contract)
        #expect(returned.contractID == accepted.contractID)
        #expect(returned.createdAt == accepted.createdAt)
        #expect(returned.expiresAt == accepted.expiresAt)
    }

    @Test func removingExpiredContractRouteJobChargesCompensation() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let accepted = try #require(state.offers.first {
            $0.source == .contract && $0.contractID == contractOffer.id
        })
        try engine.apply(.createRoute(name: "Late contract"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: accepted.id, routeID: route.id), to: &state)
        engine.advance(&state, by: state.clock.minutes(until: accepted.expiresAt))

        #expect(catalog.economy.contractPenaltyPercent == 40)
        let penalty = Money((Double(accepted.payout) * 0.40).rounded())
        let cashBeforeRemoval = state.cash
        let costBeforeRemoval = state.stats.totalCost
        let contractBeforeRemoval = try #require(state.activeContract(contractOffer.id))
        try engine.apply(.removeJobFromRoute(jobID: accepted.id, routeID: route.id), to: &state)

        let contract = try #require(state.activeContract(contractOffer.id))
        #expect(state.cash == cashBeforeRemoval - penalty)
        #expect(state.stats.totalCost == costBeforeRemoval + penalty)
        #expect(contract.shipmentsMissed == contractBeforeRemoval.shipmentsMissed + 1)
        #expect(contract.penaltiesPaid == contractBeforeRemoval.penaltiesPaid + penalty)
        #expect(state.offers.allSatisfy { $0.id != accepted.id })
        #expect(state.log.contains { entry in
            if case let .contractShipmentMissed(loggedContractID, loggedPenalty) = entry.event {
                return loggedContractID == contractOffer.id && loggedPenalty == penalty
            }
            return false
        })
    }

    @Test func deletingStoppedRouteCleansUpItsShipmentsAndReleasesVehicles() throws {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState()
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        let vehicle = try #require(state.vehicles.first)
        let spot = Fixture.laneOffer(id: 999, state: state)
        state.offers.append(spot)
        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let contractShipment = try #require(state.offers.first {
            $0.source == .contract && $0.contractID == contractOffer.id
        })
        try engine.apply(.createRoute(name: "Disposable"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: spot.id, routeID: route.id), to: &state)
        try engine.apply(.addJobToRoute(offerID: contractShipment.id, routeID: route.id), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: route.id, vehicleID: vehicle.id), to: &state)
        #expect(state.routeRuns(of: route.id).isEmpty)

        try engine.apply(.deleteRoute(route.id), to: &state)

        #expect(state.route(route.id) == nil)
        #expect(state.routeRuns(of: route.id).isEmpty)
        #expect(state.shipments(of: route.id).isEmpty)
        #expect(state.shipment(spot.id) == nil)
        #expect(state.shipment(contractShipment.id) == nil)
        #expect(state.route(of: vehicle.id) == nil)
        #expect(state.isVehicleIdle(vehicle.id))
        #expect(state.offers.allSatisfy { $0.id != spot.id })
        let returned = try #require(state.offers.first { $0.id == contractShipment.id })
        #expect(returned.expiresAt == contractShipment.expiresAt)
    }

    @Test func unattendedContractShipmentChargesCompensation() throws {
        let catalog = try Fixture.catalog()
        let engine = SimulationEngine(catalog: catalog)
        var state = Fixture.newState()
        engine.advance(&state, by: 0)

        let contractOffer = try #require(state.contractOffers.first)
        try engine.apply(.signContract(contractOffer.id), to: &state)
        // Signing grants preparation time; skip past it so the first cycle posts.
        engine.advance(&state, by: contractOffer.leadTimeMinutes)
        let cashAfterSigning = state.cash

        // No vehicle is ever assigned: the first shipment must miss its
        // deadline (one interval) and cost compensation.
        engine.advance(&state, by: contractOffer.shipmentIntervalMinutes + 10)

        let contract = try #require(state.activeContract(contractOffer.id))
        #expect(contract.shipmentsMissed >= 1)
        #expect(contract.penaltiesPaid > 0)
        #expect(state.cash == cashAfterSigning - contract.penaltiesPaid)
        #expect(state.log.contains {
            if case .contractShipmentMissed = $0.event { return true }
            return false
        })
    }
}

// MARK: - Determinism contract

struct DeterminismTests {
    private func encodedRouteState(chunks: [Int]) throws -> Data {
        let engine = SimulationEngine(catalog: try Fixture.catalog())
        var state = Fixture.newState(seed: 5_678)
        try engine.apply(.buyVehicle(Fixture.van), to: &state)
        engine.advance(&state, by: 0)

        let vehicle = try #require(state.vehicles.first)
        // A lane shuttle in the mix: dispatch claims parcels from the dock on
        // its own; the encoded state must still be chunk-invariant.
        let offer = Fixture.laneOffer(id: 999_999, state: state)
        state.offers.append(offer)
        try engine.apply(.createRoute(name: "Deterministic loop"), to: &state)
        let route = try #require(state.routes.last)
        try engine.apply(.addJobToRoute(offerID: offer.id, routeID: route.id), to: &state)
        try engine.apply(.addTravelStop(routeID: route.id, cityID: Fixture.cityA), to: &state)
        try engine.apply(.assignVehicleToRoute(routeID: route.id, vehicleID: vehicle.id), to: &state)
        try engine.apply(.startRoute(route.id), to: &state)

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
