//
//  FreightLaneTests.swift
//  Goods&GloryTests
//
//  Persistent freight lanes: deterministic derivation from the bundled
//  catalog, population-proportional city throughput, bounded weekly swing.
//

import Foundation
import Testing
@testable import Goods_Glory

struct FreightLaneTests {
    @Test func bundledLanesAreDeterministicAndWellFormed() throws {
        let first = try GameCatalog.load(from: .main)
        let second = try GameCatalog.load(from: .main)
        #expect(!first.lanes.isEmpty)
        #expect(first.lanes.map(\.id) == second.lanes.map(\.id))
        #expect(first.lanes.map(\.baseRatePerDayKg) == second.lanes.map(\.baseRatePerDayKg))

        for lane in first.lanes {
            #expect(lane.originCityID != lane.destinationCityID)
            #expect(lane.baseRatePerDayKg >= 1)
            #expect(first.firm(lane.originFirmID)?.role == .supplier)
            #expect(first.firm(lane.originFirmID)?.cityID == lane.originCityID)
            #expect(first.firm(lane.destinationFirmID)?.role == .receiver)
            #expect(first.firm(lane.destinationFirmID)?.cityID == lane.destinationCityID)
            // Lanes never cross road networks: a truck cannot drive the Atlantic.
            #expect(first.roadDistanceKm(from: lane.originCityID, to: lane.destinationCityID) != nil)
        }
    }

    @Test func cityOutboundThroughputTracksPopulation() throws {
        let catalog = try GameCatalog.load(from: .main)
        for city in catalog.cities {
            let outbound = catalog.lanes(from: city.id)
            #expect(outbound.count >= 3, "\(city.id) has too few lanes")
            #expect(outbound.count <= 16, "\(city.id) has too many lanes")

            let total = Double(outbound.reduce(0) { $0 + $1.baseRatePerDayKg })
            let budget = Double(city.population) / 100_000
                * Double(catalog.economy.lanes.cityOutboundKgPerDayPer100k)
            // The rate floor drops small-city tail lanes, so kept throughput
            // sits below budget — but never collapses and never overshoots.
            #expect(total >= budget * 0.25, "\(city.id) throughput collapsed")
            #expect(total <= budget * 1.05, "\(city.id) throughput overshoots")
        }
    }

    @Test func weeklyRateIsDeterministicAndBounded() throws {
        let catalog = try GameCatalog.load(from: .main)
        let lane = try #require(catalog.lanes.max(by: { $0.baseRatePerDayKg < $1.baseRatePerDayKg }))
        let swing = catalog.economy.lanes.weeklySwingPercent
        #expect(swing > 0)

        var sawChange = false
        for week in 0..<8 {
            let rate = lane.ratePerDayKg(week: week, worldSeed: 42, swingPercent: swing)
            #expect(rate == lane.ratePerDayKg(week: week, worldSeed: 42, swingPercent: swing))

            let base = Double(lane.baseRatePerDayKg)
            let amplitude = Double(swing) / 100
            #expect(Double(rate) >= (base * (1 - amplitude)).rounded(.down))
            #expect(Double(rate) <= (base * (1 + amplitude)).rounded(.up))
            if rate != lane.baseRatePerDayKg { sawChange = true }
        }
        #expect(sawChange, "weekly swing never moved the rate")
        #expect(lane.ratePerDayKg(week: 3, worldSeed: 1, swingPercent: 0) == lane.baseRatePerDayKg)
    }

    @Test func fixtureCatalogWithEmptyMarketsDerivesNoLanes() throws {
        // Mirrors GameCatalogTests' graph fixture: empty supply lists must not
        // trip lane validation or produce phantom lanes.
        let cityA = CityID("alpha")
        let nodeA = RoadNodeID("node_alpha")
        let cityB = CityID("beta")
        let nodeB = RoadNodeID("node_beta")
        let catalog = try GameCatalog(
            cities: [
                CityDefinition(
                    id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST",
                    latitude: 0, longitude: 0, population: 100_000,
                    hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: true
                ),
                CityDefinition(
                    id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST",
                    latitude: 0, longitude: 1, population: 100_000,
                    hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: false
                )
            ],
            networkNodes: [
                NetworkNodeDefinition(
                    id: nodeA, coordinate: GeoCoordinate(latitude: 0, longitude: 0),
                    kind: .city, cityID: cityA
                ),
                NetworkNodeDefinition(
                    id: nodeB, coordinate: GeoCoordinate(latitude: 0, longitude: 1),
                    kind: .city, cityID: cityB
                )
            ],
            roads: [
                RoadDefinition(id: RoadID("alpha_beta"), from: nodeA, to: nodeB, distanceKm: 111)
            ],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: VehicleTypeID("test_van"), name: "Test Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 2_000, volumeM3: 20), speedKmh: 100,
                    purchasePrice: 10_000, costPerKm: 0.5, driverCostPerHour: 10,
                    fixedCostPerDay: 60
                )
            ],
            products: [
                ProductDefinition(
                    id: ProductID("test_product"), name: "Test Product", symbol: "shippingbox",
                    densityM3PerTon: 2,
                    minimumShipmentMassKg: 1_000, maximumShipmentMassKg: 1_000
                )
            ],
            cityMarkets: [
                CityMarketProfile(cityID: cityA, supply: [], demand: []),
                CityMarketProfile(cityID: cityB, supply: [], demand: [])
            ],
            economy: TestEconomy.make()
        )
        #expect(catalog.lanes.isEmpty)
    }

    @Test func fixtureCatalogWithMarketsDerivesReciprocalLanes() throws {
        let cityA = CityID("alpha")
        let nodeA = RoadNodeID("node_alpha")
        let cityB = CityID("beta")
        let nodeB = RoadNodeID("node_beta")
        let product = ProductID("test_product")
        let catalog = try GameCatalog(
            cities: [
                CityDefinition(
                    id: cityA, roadNodeID: nodeA, name: "Alpha", country: "TST",
                    latitude: 0, longitude: 0, population: 2_000_000,
                    hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: true
                ),
                CityDefinition(
                    id: cityB, roadNodeID: nodeB, name: "Beta", country: "TST",
                    latitude: 0, longitude: 1, population: 2_000_000,
                    hasRailFreightAccess: true, hasAirCargoAccess: true, hasSeaPortAccess: false,
                    costIndex: 250, trafficDelayIndex: 1_000, isStarterCity: false
                )
            ],
            networkNodes: [
                NetworkNodeDefinition(
                    id: nodeA, coordinate: GeoCoordinate(latitude: 0, longitude: 0),
                    kind: .city, cityID: cityA
                ),
                NetworkNodeDefinition(
                    id: nodeB, coordinate: GeoCoordinate(latitude: 0, longitude: 1),
                    kind: .city, cityID: cityB
                )
            ],
            roads: [
                RoadDefinition(id: RoadID("alpha_beta"), from: nodeA, to: nodeB, distanceKm: 111)
            ],
            vehicleTypes: [
                VehicleTypeDefinition(
                    id: VehicleTypeID("test_van"), name: "Test Van", symbol: "box.truck",
                    capacity: LoadSize(massKg: 2_000, volumeM3: 20), speedKmh: 100,
                    purchasePrice: 10_000, costPerKm: 0.5, driverCostPerHour: 10,
                    fixedCostPerDay: 60
                )
            ],
            products: [
                ProductDefinition(
                    id: product, name: "Test Product", symbol: "shippingbox",
                    densityM3PerTon: 2,
                    minimumShipmentMassKg: 1_000, maximumShipmentMassKg: 1_000
                )
            ],
            cityMarkets: [
                CityMarketProfile(
                    cityID: cityA,
                    supply: [CityProductWeight(productID: product, weight: 100)],
                    demand: [CityProductWeight(productID: product, weight: 100)]
                ),
                CityMarketProfile(
                    cityID: cityB,
                    supply: [CityProductWeight(productID: product, weight: 100)],
                    demand: [CityProductWeight(productID: product, weight: 100)]
                )
            ],
            economy: TestEconomy.make()
        )

        // Each city supplies the product and the other demands it: one lane
        // per direction, both carrying the full city budget (30 t/day).
        #expect(catalog.lanes.count == 2)
        let aToB = try #require(catalog.lanes(from: cityA).first)
        #expect(aToB.destinationCityID == cityB)
        #expect(aToB.baseRatePerDayKg == 30_000)
        #expect(catalog.lanes(to: cityA).count == 1)
    }
}
