//
//  OfferCalibrationTests.swift
//  Goods&GloryTests
//
//  Freight-model health checks: positive util-aware profit on typical van hauls,
//  and second-vehicle reachability within ~two game weeks of steady work.
//

import Foundation
import Testing
@testable import Goods_Glory

struct OfferCalibrationTests {

    @Test func spotFreightOffersAreProfitableAtHighFill() throws {
        let catalog = try GameCatalog.load(from: .main)
        let engine = SimulationEngine(catalog: catalog)
        let van = try #require(catalog.vehicleTypes.first { $0.id.rawValue == "cargo_van" })

        var utils: [Double] = []
        var profits: [Double] = []

        for hq in catalog.starterCities.map(\.id) {
            for seed in UInt64(0)..<10 {
                let founding = catalog.city(hq).map(CityInsight.foundingCost(for:)) ?? 0
                var state = GameState.newCampaign(
                    config: CampaignConfig(
                        seed: seed,
                        identity: CompanyIdentity(
                            name: "Calib", colorHex: "#1F6FEB", emblemSymbol: "star.fill"
                        ),
                        hqCity: hq
                    ),
                    economy: catalog.economy,
                    foundingCost: founding
                )
                engine.advance(&state, by: 0)
                for offer in state.offers where offer.source == .spot {
                    let util = engine.util(load: offer.load, capacity: van.capacity)
                    utils.append(util)
                    let minutes = catalog.economy.loadingMinutes
                        + engine.travelMinutes(distanceKm: offer.distanceKm, speedKmh: van.speedKmh)
                        + catalog.economy.unloadingMinutes
                    let cost = engine.taskCost(
                        totalKm: offer.distanceKm,
                        taskMinutes: minutes,
                        vehicleType: van
                    )
                    profits.append(Double(offer.payout - cost))
                }
            }
        }

        #expect(!utils.isEmpty)
        #expect(utils.filter { $0 >= 0.45 }.count >= utils.count / 2)
        // Median direct (no-deadhead) profit should be clearly positive.
        let sorted = profits.sorted()
        let median = sorted[sorted.count / 2]
        #expect(median > 150)
    }

    @Test func steadyVanWorkCanFundSecondVehicleWithinTwoWeeks() throws {
        let catalog = try GameCatalog.load(from: .main)
        let engine = SimulationEngine(catalog: catalog)
        let van = try #require(catalog.vehicleTypes.first { $0.id.rawValue == "cargo_van" })
        let hq = try #require(catalog.starterCities.first { $0.id.rawValue == "us_chicago" })
        let founding = CityInsight.foundingCost(for: hq)

        var state = GameState.newCampaign(
            config: CampaignConfig(
                seed: 7,
                identity: CompanyIdentity(
                    name: "Climb", colorHex: "#1F6FEB", emblemSymbol: "star.fill"
                ),
                hqCity: hq.id
            ),
            economy: catalog.economy,
            foundingCost: founding
        )
        try engine.apply(.buyVehicle(van.id), to: &state)

        // Simulate ~14 game days: accept the best-looking idle-compatible offer
        // whenever a vehicle is free.
        let twoWeeks = 14 * GameState.minutesPerDay
        var cursor = 0
        while cursor < twoWeeks {
            engine.advance(&state, by: 60)
            cursor += 60
            guard let vehicle = state.vehicles.first(where: \.isAvailable) else { continue }
            let candidates = state.offers.compactMap { offer -> (JobOffer, SimulationEngine.JobEstimate)? in
                guard let estimate = engine.estimate(offer: offer, vehicle: vehicle, state: state),
                      estimate.estimatedProfit > 0 else { return nil }
                return (offer, estimate)
            }
            guard let best = candidates.max(by: { $0.1.estimatedProfit < $1.1.estimatedProfit }) else {
                continue
            }
            try engine.apply(.acceptJob(offerID: best.0.id, vehicleID: vehicle.id), to: &state)
        }

        #expect(state.cash >= van.purchasePrice)
        #expect(state.stats.deliveredJobs >= 8)
    }
}
