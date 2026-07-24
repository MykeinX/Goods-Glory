//
//  CityInsightTests.swift
//  Goods&GloryTests
//
//  Derived city presentation metrics (market, competition, founding cost).
//

import Foundation
import Testing
@testable import Goods_Glory

struct CityInsightTests {
    @Test func foundingCostScalesWithCostIndex() {
        let cheap = sampleCity(id: "cheap", population: 1_000_000, costIndex: 1_000)
        let pricey = sampleCity(id: "pricey", population: 1_000_000, costIndex: 1_155)
        #expect(CityInsight.foundingCost(for: cheap) == 22_000)
        #expect(CityInsight.foundingCost(for: pricey) == 25_410)
    }

    @Test func marketAndCompetitionNormalizeAgainstCatalogRange() throws {
        let catalog = try GameCatalog.load(from: .main)
        let smallest = try #require(catalog.cities.min(by: { $0.population < $1.population }))
        let largest = try #require(catalog.cities.max(by: { $0.population < $1.population }))

        let smallInsight = CityInsight.make(city: smallest, catalog: catalog)
        let largeInsight = CityInsight.make(city: largest, catalog: catalog)

        #expect(smallInsight.marketSizePercent == 0)
        #expect(largeInsight.marketSizePercent == 1)
        #expect(largeInsight.marketSizePercent > smallInsight.marketSizePercent)
        #expect((0...1).contains(smallInsight.competitionPercent))
        #expect((0...1).contains(largeInsight.competitionPercent))
    }

    @Test func perksFollowAccessFlags() throws {
        let catalog = try GameCatalog.load(from: .main)
        let dallas = try #require(catalog.city(CityID("us_dallas")))
        let newYork = try #require(catalog.city(CityID("us_new_york")))

        let dallasInsight = CityInsight.make(city: dallas, catalog: catalog)
        let newYorkInsight = CityInsight.make(city: newYork, catalog: catalog)

        #expect(!dallasInsight.perkLabels.contains(where: { $0.localizedCaseInsensitiveContains("sea") }))
        #expect(newYorkInsight.perkLabels.contains(where: { $0.localizedCaseInsensitiveContains("sea") }))
    }

    @Test func newCampaignDeductsFoundingCostFromStartingCash() throws {
        let catalog = try GameCatalog.load(from: .main)
        let hq = try #require(catalog.city(CityID("us_chicago")))
        let foundingCost = CityInsight.foundingCost(for: hq)

        let state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 1,
                identity: CompanyIdentity(name: "Test", colorHex: "#FFB037", emblemSymbol: "star.fill"),
                hqCity: hq.id
            ),
            economy: catalog.economy,
            foundingCost: foundingCost
        )

        #expect(state.cash == catalog.economy.startingCash - foundingCost)
        #expect(state.cash >= 14_000)
    }

    private func sampleCity(id: String, population: Int, costIndex: UInt16) -> CityDefinition {
        CityDefinition(
            id: CityID(id),
            roadNodeID: RoadNodeID("node_\(id)"),
            name: id,
            country: "TST",
            latitude: 0,
            longitude: 0,
            population: population,
            hasRailFreightAccess: false,
            hasAirCargoAccess: false,
            hasSeaPortAccess: false,
            costIndex: costIndex,
            trafficDelayIndex: 1_000,
            isStarterCity: true
        )
    }
}
