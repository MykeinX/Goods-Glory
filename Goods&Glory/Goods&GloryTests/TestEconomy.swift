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

    /// Compact facility ladder for fixtures: cheap enough that a test can
    /// afford to build, small enough that capacity limits are reachable.
    static let defaultFacilities = FacilityConfig(
        branch: [
            FacilityLevelSpec(
                level: 1, buildCost: 8_000, buildDays: 1, upkeepPerDay: 20,
                storageMassKg: 0, storageVolumeM3: 0, docks: 0,
                handlingPercent: 100, contractSlotPercent: 100, lanePremiumPercent: 0
            ),
            FacilityLevelSpec(
                level: 2, buildCost: 16_000, buildDays: 2, upkeepPerDay: 40,
                storageMassKg: 0, storageVolumeM3: 0, docks: 0,
                handlingPercent: 100, contractSlotPercent: 150, lanePremiumPercent: 0
            )
        ],
        warehouse: [
            FacilityLevelSpec(
                level: 1, buildCost: 12_000, buildDays: 1, upkeepPerDay: 30,
                storageMassKg: 60_000, storageVolumeM3: 400, docks: 2,
                handlingPercent: 100, contractSlotPercent: 100, lanePremiumPercent: 0
            ),
            FacilityLevelSpec(
                level: 2, buildCost: 24_000, buildDays: 2, upkeepPerDay: 60,
                storageMassKg: 200_000, storageVolumeM3: 1_400, docks: 4,
                handlingPercent: 90, contractSlotPercent: 100, lanePremiumPercent: 0
            )
        ]
    )

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
        spotMarginPercent: Int = 38,
        contractMarginPercent: Int = 25,
        contractPenaltyPercent: Int = 40,
        hqLanePremiumPercent: Int = 0,
        facilities: FacilityConfig = defaultFacilities,
        contractDeliveryWindowPercent: Int = 175,
        contractDeliveryWindowFloorPercent: Int = 70,
        contractLeadTimePercent: Int = 120,
        // Fixtures exercise contract rules directly, so the delivery gate is
        // off by default; the gate itself has its own test.
        contractsUnlockAfterDeliveries: Int = 0
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
            spotMarginPercent: spotMarginPercent,
            urgencyTiers: defaultUrgencyTiers,
            contractOfferIntervalMinutes: 2880,
            maxOpenContractOffers: 3,
            contractDurationDays: 14,
            contractMarginPercent: contractMarginPercent,
            contractPenaltyPercent: contractPenaltyPercent,
            hqLanePremiumPercent: hqLanePremiumPercent,
            facilities: facilities,
            contractDeliveryWindowPercent: contractDeliveryWindowPercent,
            contractDeliveryWindowFloorPercent: contractDeliveryWindowFloorPercent,
            contractLeadTimePercent: contractLeadTimePercent,
            contractsUnlockAfterDeliveries: contractsUnlockAfterDeliveries
        )
    }
}
