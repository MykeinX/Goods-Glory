//
//  SimulationEngine.swift
//  Goods&Glory
//
//  Pure simulation core. Advances only through explicit commands and explicit
//  amounts of game time. No wall clock, no UI, no persistence. The same
//  catalog, initial state, seed and command sequence always produce the same
//  resulting state.
//

import Foundation

struct SimulationEngine: Sendable {
    let catalog: GameCatalog

    init(catalog: GameCatalog) {
        self.catalog = catalog
    }

    // MARK: - Commands

    func apply(_ command: GameCommand, to state: inout GameState) throws {
        switch command {
        case .buyVehicle(let typeID):
            try buyVehicle(typeID, state: &state)
        case .dispatchVehicleToLane(let laneID, let vehicleID):
            try dispatchVehicleToLane(laneID, vehicleID: vehicleID, state: &state)
        case .installModule(let kind, let cityID):
            try installModule(kind: kind, cityID: cityID, state: &state)
        case .upgradeModule(let kind, let cityID):
            try upgradeModule(kind: kind, cityID: cityID, state: &state)
        case .removeModule(let kind, let cityID):
            try removeModule(kind: kind, cityID: cityID, state: &state)
        case .addNetworkTaskToRoute(let routeID, let visitStopID, let task):
            try addNetworkTaskToRoute(
                routeID: routeID,
                visitStopID: visitStopID,
                task: task,
                state: &state
            )
        case .createRoute(let name):
            createRoute(name: name, state: &state)
        case .renameRoute(let routeID, let name):
            try renameRoute(routeID, name: name, state: &state)
        case .addTravelStop(let routeID, let cityID):
            try addTravelStop(routeID: routeID, cityID: cityID, state: &state)
        case .removeRouteStop(let routeID, let stopID):
            try removeRouteStop(routeID: routeID, stopID: stopID, state: &state)
        case .moveRouteStop(let routeID, let stopID, let offset):
            try moveRouteStop(routeID: routeID, stopID: stopID, offset: offset, state: &state)
        case .reorderRouteVisits(let routeID, let orderedVisitIDs):
            try reorderRouteVisits(routeID: routeID, orderedVisitIDs: orderedVisitIDs, state: &state)
        case .removeRouteVisit(let routeID, let visitStopID):
            try removeRouteVisit(routeID: routeID, visitStopID: visitStopID, state: &state)
        case .assignVehicleToRoute(let routeID, let vehicleID):
            try assignVehicleToRoute(routeID: routeID, vehicleID: vehicleID, state: &state)
        case .unassignVehicleFromRoute(let routeID, let vehicleID):
            try unassignVehicleFromRoute(routeID: routeID, vehicleID: vehicleID, state: &state)
        case .startRoute(let routeID):
            try startRoute(routeID, state: &state)
        case .stopRoute(let routeID):
            try stopRoute(routeID, state: &state)
        case .deleteRoute(let routeID):
            try deleteRoute(routeID, state: &state)
        }
    }

    func buyVehicle(_ typeID: VehicleTypeID, state: inout GameState) throws {
        guard let vehicleType = catalog.vehicleType(typeID) else { throw CommandError.unknownReference }
        guard state.cash >= vehicleType.purchasePrice else {
            throw CommandError.insufficientFunds(required: vehicleType.purchasePrice)
        }
        state.cash -= vehicleType.purchasePrice
        let vehicle = Vehicle(
            id: VehicleID(rawValue: state.issueID()),
            typeID: typeID,
            cityID: state.config.hqCity,
            odometerKm: 0
        )
        state.vehicles.append(vehicle)
        state.appendLog(.vehiclePurchased(typeID: typeID, city: vehicle.cityID))
        state.recordDebug(
            .capital,
            delta: -vehicleType.purchasePrice,
            "BUY   v\(vehicle.id.rawValue) \(vehicleType.name) cap \(kg(vehicleType.capacity.massKg)) "
                + "\(money(vehicleType.purchasePrice)) upkeep \(money(Money(vehicleType.fixedCostPerDay)))/d"
        )
    }

}
