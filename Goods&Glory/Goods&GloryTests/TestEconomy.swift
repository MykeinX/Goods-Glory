//
//  TestEconomy.swift
//  Goods&GloryTests
//
//  Shared EconomyConfig / vehicle freight helpers for fixture catalogs.
//

import Foundation
@testable import Goods_Glory

enum TestEconomy {
    /// Compact facility ladder for fixtures: cheap enough that a test can
    /// afford to build, small enough that capacity limits are reachable.
    static let defaultFacilities = FacilityConfig(
        office: [
            FacilityLevelSpec(
                level: 1, buildCost: 8_000, buildDays: 1, upkeepPerDay: 20,
                storageMassKg: 0, storageVolumeM3: 0, docks: 0,
                handlingPercent: 100, lanePremiumPercent: 0
            ),
            FacilityLevelSpec(
                level: 2, buildCost: 16_000, buildDays: 2, upkeepPerDay: 40,
                storageMassKg: 0, storageVolumeM3: 0, docks: 0,
                handlingPercent: 100, lanePremiumPercent: 0
            )
        ],
        warehouse: [
            FacilityLevelSpec(
                level: 1, buildCost: 12_000, buildDays: 1, upkeepPerDay: 30,
                storageMassKg: 60_000, storageVolumeM3: 400, docks: 2,
                handlingPercent: 100, lanePremiumPercent: 0
            ),
            FacilityLevelSpec(
                level: 2, buildCost: 24_000, buildDays: 2, upkeepPerDay: 60,
                storageMassKg: 200_000, storageVolumeM3: 1_400, docks: 4,
                handlingPercent: 90, lanePremiumPercent: 0
            )
        ],
        dock: [
            FacilityLevelSpec(
                level: 1, buildCost: 6_000, buildDays: 1, upkeepPerDay: 15,
                storageMassKg: 0, storageVolumeM3: 0, docks: 2,
                handlingPercent: 80, lanePremiumPercent: 0
            )
        ],
        racking: [
            FacilityLevelSpec(
                level: 1, buildCost: 5_000, buildDays: 1, upkeepPerDay: 12,
                storageMassKg: 30_000, storageVolumeM3: 200, docks: 0,
                handlingPercent: 100, lanePremiumPercent: 0
            )
        ],
        forklift: [
            FacilityLevelSpec(
                level: 1, buildCost: 3_000, buildDays: 1, upkeepPerDay: 8,
                storageMassKg: 0, storageVolumeM3: 0, docks: 0,
                handlingPercent: 85, lanePremiumPercent: 0
            )
        ]
    )

    static func make(
        startingCash: Money = 20_000,
        loadingMinutes: Int = 30,
        unloadingMinutes: Int = 30,
        fillFloor: Double = 0.5,
        emptyReturnSharePercent: Int = 85,
        spotMarginPercent: Int = 55,
        hqLanePremiumPercent: Int = 0,
        facilities: FacilityConfig = defaultFacilities,
        lanes: LaneConfig = defaultLanes
    ) -> EconomyConfig {
        EconomyConfig(
            startingCash: startingCash,
            loadingMinutes: loadingMinutes,
            unloadingMinutes: unloadingMinutes,
            fillFloor: fillFloor,
            emptyReturnSharePercent: emptyReturnSharePercent,
            spotMarginPercent: spotMarginPercent,
            hqLanePremiumPercent: hqLanePremiumPercent,
            facilities: facilities,
            lanes: lanes
        )
    }

    /// Mirrors the bundled economy.json lane block so fixture-derived lanes
    /// stay in the same band as the real catalog.
    static let defaultLanes = LaneConfig(
        cityOutboundKgPerDayPer100k: 1_500,
        minimumRatePerDayKg: 2_000,
        weeklySwingPercent: 25,
        distanceHalfWeightKm: 900,
        parcelPatienceMinutes: 2_160
    )
}
