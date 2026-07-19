//
//  TestEconomy.swift
//  Goods&GloryTests
//
//  Shared EconomyConfig / vehicle freight helpers for fixture catalogs.
//

import Foundation
@testable import Goods_Glory

enum TestEconomy {
    static let defaultUrgencyTiers: [UrgencyTier] = [
        UrgencyTier(id: "economy", multiplier: 0.85, lifetimeMinutes: 1440, weight: 30),
        UrgencyTier(id: "normal", multiplier: 1.0, lifetimeMinutes: 720, weight: 50),
        UrgencyTier(id: "urgent", multiplier: 1.45, lifetimeMinutes: 300, weight: 20)
    ]

    static func make(
        startingCash: Money = 20_000,
        loadingMinutes: Int = 30,
        unloadingMinutes: Int = 30,
        offerGenerationIntervalMinutes: Int = 480,
        offerLifetimeMinutes: Int = 720,
        offerChancePercent: Int = 100,
        maxOpenOffersPerCity: Int = 3,
        offerSlotPopulation: Int = 4_500_000,
        fillFloor: Double = 0.6,
        contractMarginPercent: Int = 25,
        contractPenaltyPercent: Int = 40
    ) -> EconomyConfig {
        EconomyConfig(
            startingCash: startingCash,
            loadingMinutes: loadingMinutes,
            unloadingMinutes: unloadingMinutes,
            offerGenerationIntervalMinutes: offerGenerationIntervalMinutes,
            offerLifetimeMinutes: offerLifetimeMinutes,
            offerChancePercent: offerChancePercent,
            maxOpenOffersPerCity: maxOpenOffersPerCity,
            offerSlotPopulation: offerSlotPopulation,
            fillFloor: fillFloor,
            urgencyTiers: defaultUrgencyTiers,
            contractOfferIntervalMinutes: 2880,
            maxOpenContractOffers: 3,
            contractDurationDays: 14,
            contractMarginPercent: contractMarginPercent,
            contractPenaltyPercent: contractPenaltyPercent
        )
    }
}
