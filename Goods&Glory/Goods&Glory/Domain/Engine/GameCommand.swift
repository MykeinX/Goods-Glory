//
//  GameCommand.swift
//  Goods&Glory
//
//  Player intents applied to the simulation. The UI never mutates GameState
//  directly; it produces commands that the engine validates and applies.
//

import Foundation

enum ContractRouteAction: Equatable, Sendable {
    case pickup
    case deliver
}

enum GameCommand: Sendable {
    /// Buy a vehicle; it is delivered at the company HQ city.
    case buyVehicle(VehicleTypeID)
    /// Accept an open spot offer and assign an idle vehicle to it.
    /// If the vehicle is in another city it first drives there empty.
    case acceptJob(offerID: JobID, vehicleID: VehicleID)
    /// Sign an open long-term contract; shipments post periodically as job offers.
    case signContract(ContractID)
    /// Dedicate a vehicle to a signed contract. Auto-creates and starts the
    /// contract's two-stop route on first assignment.
    case assignVehicleToContract(contractID: ContractID, vehicleID: VehicleID)
    /// Release a vehicle from a contract route (delegates to route unassign).
    case unassignVehicleFromContract(contractID: ContractID, vehicleID: VehicleID)

    // MARK: Routes

    /// Create an empty, stopped route.
    case createRoute(name: String)
    case renameRoute(routeID: RouteID, name: String)
    /// Append a plain travel stop. Allowed while running (appending is safe).
    case addTravelStop(routeID: RouteID, cityID: CityID)
    /// Remove a stop. Route must be stopped; shipment stops are removed via
    /// removeJobFromRoute so cargo bookkeeping stays consistent.
    case removeRouteStop(routeID: RouteID, stopID: Int)
    /// Move a stop one position up (-1) or down (+1). Route must be stopped.
    case moveRouteStop(routeID: RouteID, stopID: Int, offset: Int)
    /// Add one recurring contract action to an existing city visit. The visit
    /// id is the first stop id in its consecutive same-city block.
    case addContractTaskToRoute(
        routeID: RouteID,
        visitStopID: Int,
        contractID: ContractID,
        action: ContractRouteAction
    )
    /// Replace the city-visit order atomically. Every current visit id must
    /// appear exactly once.
    case reorderRouteVisits(routeID: RouteID, orderedVisitIDs: [Int])
    /// Remove one whole city visit and all of its local tasks.
    case removeRouteVisit(routeID: RouteID, visitStopID: Int)
    /// Accept a market offer into a route: appends pickup + deliver stops.
    case addJobToRoute(offerID: JobID, routeID: RouteID)
    /// Detach an accepted, not-yet-loaded shipment; contract shipments return
    /// to the market with their original deadline.
    case removeJobFromRoute(jobID: JobID, routeID: RouteID)
    case assignVehicleToRoute(routeID: RouteID, vehicleID: VehicleID)
    /// Wind down the vehicle's run: no new pickups, deliver carried cargo, release.
    case unassignVehicleFromRoute(routeID: RouteID, vehicleID: VehicleID)
    case startRoute(RouteID)
    /// Stop the route: all runs wind down; vehicles release once empty.
    case stopRoute(RouteID)
    /// Cancel and delete a route. Active runs stop taking pickups, finish
    /// committed cargo, release their vehicles, then purge the definition.
    /// A route with no active runs is removed immediately.
    case deleteRoute(RouteID)
}

enum CommandError: Error, Equatable, Sendable {
    case unknownReference
    case insufficientFunds(required: Money)
    case vehicleBusy
    case offerExpired
    case loadExceedsCapacity
    case noRoute
    /// A route needs at least one assigned vehicle before it can run.
    case noVehicleAssigned
    /// Direct contract cargo must have both pickup and delivery actions.
    case incompleteRouteTasks
    /// The vehicle already serves another route.
    case vehicleAlreadyAssigned
    /// Structural route edits require the route to be stopped first.
    case routeIsRunning
}
