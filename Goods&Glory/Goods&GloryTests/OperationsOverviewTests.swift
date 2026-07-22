//
//  OperationsOverviewTests.swift
//  Goods&GloryTests
//
//  The per-city operations aggregation: what each city is owed, what is on its
//  way, and where the fleet stands. The screen reading these numbers is only
//  useful if freight is counted exactly once, on the right side.
//

import Foundation
import Testing
@testable import Goods_Glory

struct OperationsOverviewTests {
    // MARK: Fixture

    private struct Setup {
        var state: GameState
        let hq: CityID
        let other: CityID
    }

    private func newState(catalog: GameCatalog) throws -> Setup {
        let hq = try #require(catalog.cities.first { $0.isStarterCity } ?? catalog.cities.first)
        let other = try #require(catalog.cities.first { $0.id != hq.id })
        let state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 7,
                identity: CompanyIdentity(name: "Ops Co", colorHex: "#1F6FEB", emblemSymbol: "star.fill"),
                hqCity: hq.id
            ),
            economy: catalog.economy
        )
        return Setup(state: state, hq: hq.id, other: other.id)
    }

    private func offer(
        id: Int,
        from origin: CityID,
        to destination: CityID,
        massKg: Int,
        payout: Money = 1_000,
        clock: GameTime,
        windowMinutes: Int = 2_000
    ) -> JobOffer {
        JobOffer(
            id: JobID(rawValue: id),
            origin: origin,
            destination: destination,
            productID: ProductID("test_product"),
            load: LoadSize(massKg: massKg, volumeM3: 1),
            payout: payout,
            distanceKm: 100,
            urgency: .normal,
            source: .contract,
            contractID: nil,
            laneID: nil,
            originFirmID: nil,
            destinationFirmID: nil,
            createdAt: clock,
            expiresAt: clock + windowMinutes
        )
    }

    // MARK: Tests

    @Test func waitingFreightCountsAgainstItsOriginCity() throws {
        let catalog = try GameCatalog.load(from: .main)
        var setup = try newState(catalog: catalog)
        setup.state.offers = [
            offer(id: 1, from: setup.hq, to: setup.other, massKg: 1_200, clock: setup.state.clock),
            offer(id: 2, from: setup.hq, to: setup.other, massKg: 800, clock: setup.state.clock)
        ]

        let overview = OperationsOverview.make(state: setup.state, catalog: catalog)
        let origin = try #require(overview.cities.first { $0.cityID == setup.hq })

        #expect(origin.waitingKg == 2_000)
        #expect(origin.waitingParcels == 2)
        #expect(origin.inboundKg == 0)
        #expect(overview.waitingKg == 2_000)
        // Nothing has been picked up, so nothing is in transit.
        #expect(overview.inTransitKg == 0)
        #expect(overview.payoutOnBoard == 0)
    }

    @Test func loadedCargoIsOutboundAtOriginAndInboundAtDestination() throws {
        let catalog = try GameCatalog.load(from: .main)
        var setup = try newState(catalog: catalog)
        let vehicleID = VehicleID(rawValue: 1)
        setup.state.vehicles = [
            Vehicle(
                id: vehicleID,
                typeID: try #require(catalog.vehicleTypes.first).id,
                cityID: setup.hq,
                assignedJobID: nil,
                odometerKm: 0
            )
        ]
        let carried = offer(id: 3, from: setup.hq, to: setup.other, massKg: 900, payout: 750, clock: setup.state.clock)
        setup.state.shipments = [
            Shipment(id: carried.id, offer: carried, location: .vehicle(vehicleID), assignedRouteID: nil)
        ]

        let overview = OperationsOverview.make(state: setup.state, catalog: catalog)
        let origin = try #require(overview.cities.first { $0.cityID == setup.hq })
        let destination = try #require(overview.cities.first { $0.cityID == setup.other })

        #expect(origin.outboundKg == 900)
        #expect(origin.waitingKg == 0, "cargo already loaded must not also count as waiting")
        #expect(destination.inboundKg == 900)
        #expect(destination.inboundParcels == 1)
        #expect(overview.inTransitKg == 900)
        #expect(overview.payoutOnBoard == 750)
    }

    @Test func freightWithNoTruckAnywhereNearItIsStalled() throws {
        let catalog = try GameCatalog.load(from: .main)
        var setup = try newState(catalog: catalog)
        setup.state.offers = [offer(id: 4, from: setup.hq, to: setup.other, massKg: 500, clock: setup.state.clock)]
        setup.state.vehicles = []

        let overview = OperationsOverview.make(state: setup.state, catalog: catalog)
        let origin = try #require(overview.cities.first { $0.cityID == setup.hq })
        #expect(origin.isStalled)

        // Park a truck there and the alarm clears without the freight moving.
        setup.state.vehicles = [
            Vehicle(
                id: VehicleID(rawValue: 2),
                typeID: try #require(catalog.vehicleTypes.first).id,
                cityID: setup.hq,
                assignedJobID: nil,
                odometerKm: 0
            )
        ]
        let calmer = OperationsOverview.make(state: setup.state, catalog: catalog)
        let parked = try #require(calmer.cities.first { $0.cityID == setup.hq })
        #expect(!parked.isStalled)
        #expect(parked.vehiclesHere == 1)
        #expect(parked.idleHere == 1)
        #expect(calmer.idleVehicles == 1)
    }

    /// The alarm is about the network, not about where a truck stands this
    /// second: a city a running route calls at is covered even while its truck
    /// is away on the far leg. Counting only trucks made well-served cities
    /// blink "no truck" every lap.
    @Test func aCityOnARunningRouteIsNotReportedAsStranded() throws {
        let catalog = try GameCatalog.load(from: .main)
        var setup = try newState(catalog: catalog)
        setup.state.offers = [
            offer(id: 7, from: setup.hq, to: setup.other, massKg: 900, clock: setup.state.clock)
        ]
        setup.state.vehicles = []

        let stranded = try #require(
            OperationsOverview.make(state: setup.state, catalog: catalog)
                .cities.first { $0.cityID == setup.hq }
        )
        #expect(stranded.isStalled)

        setup.state.routes = [
            Route(
                id: RouteID(rawValue: 99),
                name: "Sweep",
                stops: [RouteStop(id: 1, cityID: setup.hq, task: .dropToWarehouse)],
                vehicleIDs: [],
                isRunning: true
            )
        ]
        let covered = try #require(
            OperationsOverview.make(state: setup.state, catalog: catalog)
                .cities.first { $0.cityID == setup.hq }
        )
        #expect(!covered.isStalled)
        #expect(covered.routesServing == 1)
    }

    @Test func theWorldsUnservedFreightIsNotTheCompanysOperation() throws {
        let catalog = try GameCatalog.load(from: .main)
        var setup = try newState(catalog: catalog)
        let engine = SimulationEngine(catalog: catalog)
        // Three days of lane accrual fills docks in every city in the catalog.
        engine.advance(&setup.state, by: 3 * GameState.minutesPerDay)
        #expect(
            setup.state.laneAccrualKg.values.count(where: { $0 > 0 }) > catalog.cities.count,
            "fixture assumption: the world should be accruing freight by now"
        )

        let overview = OperationsOverview.make(state: setup.state, catalog: catalog)
        // The company has one building and nothing else, so one row at most —
        // never a row per city on the map.
        #expect(overview.cities.count <= 1)
        #expect(overview.cities.allSatisfy { $0.cityID == setup.hq })
    }

    @Test func rowsAreOrderedByTonnageSoTheyDoNotJumpAround() throws {
        let catalog = try GameCatalog.load(from: .main)
        var setup = try newState(catalog: catalog)
        let third = try #require(
            catalog.cities.first { $0.id != setup.hq && $0.id != setup.other }?.id
        )
        setup.state.offers = [
            offer(id: 5, from: setup.other, to: setup.hq, massKg: 300, clock: setup.state.clock),
            offer(id: 6, from: third, to: setup.hq, massKg: 4_000, clock: setup.state.clock)
        ]

        let overview = OperationsOverview.make(state: setup.state, catalog: catalog)
        let order = overview.cities.map(\.throughputKg)
        #expect(order == order.sorted(by: >))
        #expect(overview.cities.first?.cityID == third)
    }
}
