//
//  CityOperationsDetail.swift
//  Goods&Glory
//
//  The drill-down behind one row of the operations overview: which parcels are
//  stuck here, which are on their way, and which trucks are standing in the
//  city. Computed on demand — only the expanded row pays for it.
//

import Foundation

struct CityOperationsDetail: Equatable, Sendable {
    /// One parcel, told from this city's point of view.
    struct Movement: Identifiable, Equatable, Sendable {
        let id: JobID
        /// Where it came from (inbound) or where it is going (waiting).
        let counterpartCityID: CityID
        let productID: ProductID
        let massKg: Int
        let payout: Money
        /// Minutes left on the delivery window. Zero means the window is gone.
        let minutesToDeadline: Int
    }

    /// Freight sitting here with no truck holding it yet.
    let waiting: [Movement]
    /// Freight riding towards this city.
    let inbound: [Movement]
    /// Trucks standing in the city right now.
    let vehicleIDs: [VehicleID]

    static let empty = CityOperationsDetail(waiting: [], inbound: [], vehicleIDs: [])

    /// Long lists defeat the purpose of the row; the tightest few carry the story.
    static let listLimit = 6

    static func make(cityID: CityID, state: GameState) -> CityOperationsDetail {
        var waiting: [Movement] = []
        var inbound: [Movement] = []

        var cityByFacility: [FacilityID: CityID] = [:]
        cityByFacility.reserveCapacity(state.facilities.count)
        for facility in state.facilities { cityByFacility[facility.id] = facility.cityID }

        for shipment in state.shipments {
            let offer = shipment.offer
            switch shipment.location {
            case .address(let at):
                guard at == cityID else { continue }
                waiting.append(movement(offer, counterpart: offer.destination, clock: state.clock))
            case .warehouse(let facilityID):
                guard cityByFacility[facilityID] == cityID else { continue }
                waiting.append(movement(offer, counterpart: offer.destination, clock: state.clock))
            case .vehicle:
                guard offer.destination == cityID else { continue }
                inbound.append(movement(offer, counterpart: offer.origin, clock: state.clock))
            }
        }

        // Indexed rather than `physicalCity(of:)` per vehicle, which would
        // rescan the route-run list for every truck in the fleet.
        var runByVehicle: [VehicleID: RouteRun] = [:]
        for run in state.routeRuns { runByVehicle[run.vehicleID] = run }

        let parked = state.vehicles
            .filter { vehicle in
                if let run = runByVehicle[vehicle.id] {
                    return run.phase != .traveling && vehicle.cityID == cityID
                }
                return vehicle.cityID == cityID
            }
            .map(\.id)

        return CityOperationsDetail(
            waiting: Array(waiting.sorted { $0.minutesToDeadline < $1.minutesToDeadline }.prefix(listLimit)),
            inbound: Array(inbound.sorted { $0.minutesToDeadline < $1.minutesToDeadline }.prefix(listLimit)),
            vehicleIDs: parked
        )
    }

    private static func movement(
        _ offer: JobOffer,
        counterpart: CityID,
        clock: GameTime
    ) -> Movement {
        Movement(
            id: offer.id,
            counterpartCityID: counterpart,
            productID: offer.productID,
            massKg: offer.load.massKg,
            payout: offer.payout,
            minutesToDeadline: max(0, clock.minutes(until: offer.expiresAt))
        )
    }
}
