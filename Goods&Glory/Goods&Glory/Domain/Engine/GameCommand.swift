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

    /// Sends an idle vehicle onto a persistent freight lane: creates and starts
    /// a two-stop shuttle route (claim at the origin dock, deliver that lane at
    /// the destination) that keeps serving the lane until stopped.
    case dispatchVehicleToLane(laneID: LaneID, vehicleID: VehicleID)

    // MARK: Facilities

    /// Start construction in a city. Cost and duration come from that city's
    /// own catalog data, so the same building is not the same price twice.
    case installModule(kind: FacilityModuleKind, cityID: CityID)
    /// Start a level upgrade. The facility keeps serving at its current level.
    case upgradeModule(kind: FacilityModuleKind, cityID: CityID)
    /// Tear down a facility. HQ cannot be demolished and a warehouse must be
    /// empty first — the game never silently destroys cargo.
    case removeModule(kind: FacilityModuleKind, cityID: CityID)

    // MARK: Routes

    /// Create an empty, stopped route.
    case createRoute(name: String)
    case renameRoute(routeID: RouteID, name: String)
    /// Append a plain travel stop. Allowed while running (appending is safe).
    case addTravelStop(routeID: RouteID, cityID: CityID)
    /// Remove a stop. Route must be stopped.
    case removeRouteStop(routeID: RouteID, stopID: Int)
    /// Move a stop one position up (-1) or down (+1). Route must be stopped.
    case moveRouteStop(routeID: RouteID, stopID: Int, offset: Int)
    /// Add a lane, warehouse or bulk-delivery action to an existing city visit.
    case addNetworkTaskToRoute(routeID: RouteID, visitStopID: Int, task: RouteTask)
    /// Replace the city-visit order atomically. Every current visit id must
    /// appear exactly once.
    case reorderRouteVisits(routeID: RouteID, orderedVisitIDs: [Int])
    /// Remove one whole city visit and all of its local tasks.
    case removeRouteVisit(routeID: RouteID, visitStopID: Int)
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
    case noRoute
    /// A route needs at least one assigned vehicle before it can run.
    case noVehicleAssigned
    /// A lane pickup must have a delivery or warehouse hand-off.
    case incompleteRouteTasks
    /// The vehicle already serves another route.
    case vehicleAlreadyAssigned
    /// Structural route edits require the route to be stopped first.
    case routeIsRunning
    /// A facility of this kind already stands in the city.
    case facilityAlreadyExists
    /// The facility is still under construction, or already at max level.
    case facilityNotAvailable
    /// A module that depends on an office cannot be built before the office.
    case officeRequired
    /// This city has no warehouse to store or collect cargo.
    case warehouseRequired
    /// A warehouse must be emptied before it can be demolished.
    case warehouseNotEmpty
    /// Something on this site is built onto the module being removed.
    case dependentModuleExists(FacilityModuleKind)
    /// Headquarters cannot be torn down.
    case cannotDemolishHeadquarters
}
