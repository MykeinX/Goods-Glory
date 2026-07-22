//
//  SimulationEngine+Standing.swift
//  Goods&Glory
//
//  Costs that accrue whether or not anything moves, plus the expiry and
//  penalty settlement of obligations nobody collected.
//

import Foundation

extension SimulationEngine {
    // MARK: - Fixed ownership costs

    func chargeFixedCostsIfNeeded(state: inout GameState) {
        let currentDay = state.clock.totalMinutes / GameState.minutesPerDay
        let days = currentDay - state.lastFixedCostDay
        // Facilities keep costing money even with no fleet: an idle warehouse
        // bleeding upkeep is exactly the pressure the expansion decision needs.
        let hasStandingCosts = !state.vehicles.isEmpty
            || state.facilities.contains { facility in
                facility.modules.contains { !(facility.isHeadquarters && $0.kind == .office) }
            }
        guard days > 0, hasStandingCosts else {
            state.lastFixedCostDay = max(state.lastFixedCostDay, currentDay)
            return
        }
        var dailyTotal = 0.0
        for vehicle in state.vehicles {
            if let type = catalog.vehicleType(vehicle.typeID) {
                dailyTotal += type.fixedCostPerDay
            }
        }
        // Under-construction facilities already pay their way: upkeep starts
        // when the site does, matching how a real lease begins at handover.
        for facility in state.facilities {
            for module in facility.modules where module.isOperational(at: state.clock) {
                guard let quote = quote(
                    kind: module.kind, level: module.level, city: facility.cityID
                ) else { continue }
                dailyTotal += Double(quote.upkeepPerDay)
            }
        }
        let charge = Money((dailyTotal * Double(days)).rounded())
        state.cash -= charge
        state.stats.totalCost += charge
        state.lastFixedCostDay = currentDay
        let fleetDaily = state.vehicles.reduce(0.0) {
            $0 + (catalog.vehicleType($1.typeID)?.fixedCostPerDay ?? 0)
        }
        state.recordDebug(
            .standing,
            delta: -charge,
            "STAND \(days)d fleet×\(state.vehicles.count) \(money(Money(fleetDaily.rounded())))/d "
                + "estate×\(state.facilities.count) \(money(Money((dailyTotal - fleetDaily).rounded())))/d "
                + "→ \(money(charge))"
        )
    }

    // MARK: - Spot offer generation

    func removeExpiredOffers(state: inout GameState) {
        let expired = state.offers.filter { $0.expiresAt <= state.clock }
        guard !expired.isEmpty else { return }
        state.offers.removeAll { $0.expiresAt <= state.clock }
        // Contract shipments are obligations: missing the deadline costs compensation.
        for offer in expired where offer.source == .contract {
            chargeMissedShipment(offer: offer, state: &state)
        }
    }

    func chargeMissedShipment(offer: JobOffer, state: inout GameState) {
        guard let contractID = offer.contractID else { return }
        let percent = Double(catalog.economy.contractPenaltyPercent) / 100
        let penalty = Money(max(0, (Double(offer.payout) * percent).rounded()))
        state.cash -= penalty
        state.stats.totalCost += penalty
        if let index = state.activeContracts.firstIndex(where: { $0.id == contractID }) {
            state.activeContracts[index].shipmentsMissed += 1
            state.activeContracts[index].penaltiesPaid += penalty
        }
        state.appendLog(.contractShipmentMissed(contractID: contractID, penalty: penalty))
        state.recordDebug(
            .charge,
            delta: -penalty,
            "MISS  c\(contractID.rawValue) \(short(offer.origin))→\(short(offer.destination)) "
                + "\(kg(offer.load.massKg)) penalty \(money(penalty)) (payout was \(money(offer.payout)))"
        )
    }

    func removeExpiredContractOffers(state: inout GameState) {
        state.contractOffers.removeAll { $0.expiresAt <= state.clock }
    }

}
