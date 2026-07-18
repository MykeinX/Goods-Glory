//
//  GameCommand.swift
//  Goods&Glory
//
//  Player intents applied to the simulation. The UI never mutates GameState
//  directly; it produces commands that the engine validates and applies.
//

import Foundation

enum GameCommand: Sendable {
    /// Buy a vehicle; it is delivered at the company HQ city.
    case buyVehicle(VehicleTypeID)
    /// Accept an open spot offer and assign an idle vehicle to it.
    /// If the vehicle is in another city it first drives there empty.
    case acceptJob(offerID: JobID, vehicleID: VehicleID)
}

enum CommandError: Error, Equatable, Sendable {
    case unknownReference
    case insufficientFunds(required: Money)
    case vehicleBusy
    case offerExpired
    case loadExceedsCapacity
    case noRoute
}
