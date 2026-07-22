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
    case jobAccepted(jobID: JobID, origin: CityID, destination: CityID)
    /// Loading finished; cargo is on the vehicle and travel begins.
    case jobPickedUp(jobID: JobID, origin: CityID, destination: CityID)
    case jobDelivered(jobID: JobID, destination: CityID, revenue: Money, cost: Money)
    case contractSigned(contractID: ContractID, origin: CityID, destination: CityID)
    case vehicleAssignedToRoute(vehicleID: VehicleID, routeID: RouteID)
    case vehicleUnassignedFromRoute(vehicleID: VehicleID, routeID: RouteID)
    case routeStarted(routeID: RouteID)
    case routeStopped(routeID: RouteID)
    /// A route shipment was delivered at its destination address.
    case routeShipmentDelivered(routeID: RouteID, jobID: JobID, destination: CityID, revenue: Money)
    /// A pickup was skipped (cargo missing or vehicle full); the lap continues.
    case routeShipmentSkipped(routeID: RouteID, jobID: JobID)
    /// A contract shipment passed its deadline undelivered; compensation charged.
    case contractShipmentMissed(contractID: ContractID, penalty: Money)
    case contractEnded(contractID: ContractID, completed: Int, missed: Int)
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
    /// Safe close requested on an open-ended contract.
    case contractCancellationRequested(contractID: ContractID)
    /// A route still has stops for a contract that ended. The route keeps
    /// running — lane stops still earn at the spot rate — but the dead stops
    /// deserve a look.
    case routeNeedsReview(routeID: RouteID, contractID: ContractID)
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
    /// Tonnage actually delivered on each lane. This is the company's record
    /// with the firms on that lane — the thing a shipper would look at before
    /// offering to reserve part of its output for you.
    var deliveredKgByLane: [LaneID: Int] = [:]
}
