//
//  CampaignLog.swift
//  Goods&Glory
//
//  The campaign log: what happened, in the player's terms.
//

import Foundation

enum LogEvent: Codable, Sendable {
    case companyFounded(city: CityID)
    case vehiclePurchased(typeID: VehicleTypeID, city: CityID)
    /// Loading finished; cargo is on the vehicle and travel begins.
    case jobPickedUp(jobID: JobID, origin: CityID, destination: CityID)
    case vehicleAssignedToRoute(vehicleID: VehicleID, routeID: RouteID)
    case vehicleUnassignedFromRoute(vehicleID: VehicleID, routeID: RouteID)
    case routeStarted(routeID: RouteID)
    case routeStopped(routeID: RouteID)
    /// A route shipment was delivered at its destination address.
    case routeShipmentDelivered(routeID: RouteID, jobID: JobID, destination: CityID, revenue: Money)
    /// Construction started. Nothing is granted until it completes.
    case facilityConstructionStarted(facilityID: FacilityID, kind: FacilityModuleKind, city: CityID, level: Int)
    case facilityCompleted(facilityID: FacilityID, kind: FacilityModuleKind, city: CityID, level: Int)
    case facilityDemolished(kind: FacilityModuleKind, city: CityID)
    /// Parcels were stored in a warehouse mid-journey.
    case cargoStored(city: CityID, parcels: Int, massKg: Int)
    /// Parcels were collected from a warehouse for their onward leg.
    case cargoLoadedFromWarehouse(city: CityID, parcels: Int, massKg: Int)
    /// A drop was refused because the warehouse had no room left.
    case warehouseFull(city: CityID, refusedParcels: Int)
}

struct LogEntry: Codable, Identifiable, Sendable {
    let id: Int
    let at: GameTime
    let event: LogEvent
}

struct CampaignStats: Codable, Sendable {
    var deliveredJobs: Int = 0
    var totalRevenue: Money = 0
    var totalCost: Money = 0
}
