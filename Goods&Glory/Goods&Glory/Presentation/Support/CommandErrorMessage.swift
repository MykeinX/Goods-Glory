//
//  CommandErrorMessage.swift
//  Goods&Glory
//
//  One place a rejected command turns into a sentence. The city popup and the
//  city screen each carried their own partial switch; when a case was added
//  only one of them learned about it.
//

import SwiftUI

enum CommandErrorMessage {
    static func text(_ error: CommandError?) -> LocalizedStringKey {
        switch error {
        case .insufficientFunds(let required): "You need \(Format.money(required)) for this."
        case .vehicleBusy: "That vehicle is already on a job."
        case .offerExpired: "The offer expired."
        case .loadExceedsCapacity: "The load does not fit this vehicle."
        case .noRoute: "No road connection to the pickup city."
        case .noVehicleAssigned: "That route has no vehicle assigned."
        case .incompleteRouteTasks: "The route is missing a pickup or a delivery."
        case .vehicleAlreadyAssigned, .routeIsRunning: "That vehicle is not available."
        case .branchRequired: "You need a branch in this city to take contracts here."
        case .warehouseRequired: "This city has no warehouse."
        case .facilityAlreadyExists: "You already have that building here."
        case .facilityNotAvailable: "That building is busy or already at its top level."
        case .warehouseNotEmpty: "Empty the warehouse before tearing it down."
        case .dependentModuleExists(let kind):
            "Remove the \(Format.moduleName(kind).lowercased()) first — it is built onto this."
        case .cannotDemolishHeadquarters: "Headquarters cannot be demolished."
        case .unknownReference, nil: "That is no longer available."
        }
    }
}
