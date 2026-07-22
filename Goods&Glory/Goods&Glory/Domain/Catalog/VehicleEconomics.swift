//
//  VehicleEconomics.swift
//  Goods&Glory
//
//  What a vehicle class costs to run, derived from the numbers it already
//  carries. The shop was listing capacity and price and leaving the player to
//  guess the rest — but the decision between two trucks is an efficiency
//  decision, and efficiency was the one thing not on screen.
//
//  No new balance parameters: everything here is arithmetic over costPerKm,
//  driverCostPerHour, speed and capacity.
//

import Foundation

extension VehicleTypeDefinition {
    /// Cost of one kilometre on the road: fuel and wear plus the driver's time
    /// at cruising speed. The number that decides a long lane.
    var operatingCostPerKm: Double {
        guard speedKmh > 0 else { return costPerKm }
        return costPerKm + driverCostPerHour / speedKmh
    }

    /// Cost of moving one tonne one kilometre with the vehicle full. This is
    /// the only fair way to compare classes: a semi costs more per km and less
    /// per tonne, and which one wins depends on whether you can fill it.
    var costPerTonneKm: Double {
        let tonnes = Double(capacity.massKg) / 1000
        guard tonnes > 0 else { return operatingCostPerKm }
        return operatingCostPerKm / tonnes
    }

    /// Standing cost of ownership, whether or not the truck moves.
    var idleCostPerDay: Double { fixedCostPerDay }
}
