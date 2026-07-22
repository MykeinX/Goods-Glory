//
//  Contracts.swift
//  Goods&Glory
//
//  Contract value types: what a commitment says, and the terms shared by
//  an open offer and a signed agreement.
//

import Foundation

/// How a contract shapes its recurring freight. The archetype decides the
/// shipment calendar and volume, not the physical work — every archetype
/// ultimately posts ordinary parcels that vehicles and routes carry.
enum ContractArchetype: String, Codable, Hashable, Sendable, CaseIterable {
    /// Steady lane: a moderate volume moves on a fixed cadence, A to B.
    case laneRecurring
    /// Periodic bulk: one large volume per cycle, far beyond a single vehicle.
    case bulkPeriodic
    /// Open-ended lane with no end date; runs until safely cancelled.
    case evergreen
    /// One source feeding several destinations by share. Forces a hub network.
    case multiDrop
}

/// One delivery endpoint of a contract, and the freight lane it commits.
///
/// A contract never invents demand: each endpoint locks a share of an existing
/// firm-to-firm lane. That share stops accruing at the dock as spot freight and
/// is posted as contract parcels instead, so the same tonnage is never sold
/// twice. Single-destination contracts carry exactly one of these; `multiDrop`
/// carries several with shares summing to 10 000.
struct ContractDestination: Codable, Hashable, Sendable {
    let cityID: CityID
    /// Receiving firm address in that city.
    let firmID: FirmID?
    /// The lane this endpoint commits.
    let laneID: LaneID
    /// Share of that lane's daily rate committed, in basis points.
    let committedShareBps: Int
    /// Share of the cycle volume in basis points. All shares sum to 10 000.
    let shareBps: Int
    let distanceKm: Double
    /// Revenue for one full `parcelMassKg` parcel delivered here. Partial
    /// parcels settle pro rata by mass.
    let payoutPerParcel: Money

    static let fullShareBps = 10_000
}

/// Fields shared by open offers and signed contracts, so pricing, UI and the
/// shipment scheduler can treat both through one interface.
protocol ContractTerms {
    var origin: CityID { get }
    var productID: ProductID { get }
    var archetype: ContractArchetype { get }
    var destinations: [ContractDestination] { get }
    var referenceVehicleTypeID: VehicleTypeID { get }
    var parcelMassKg: Int { get }
    var volumePerCycleKg: Int { get }
    var shipmentIntervalMinutes: Int { get }
    var deliveryWindowMinutes: Int { get }
    var originFirmID: FirmID? { get }
}

extension ContractTerms {
    /// Convenience view for single-destination contracts, which stay the
    /// common case across UI and tests.
    var destination: CityID { destinations.first?.cityID ?? origin }
    var destinationFirmID: FirmID? { destinations.first?.firmID }
    var distanceKm: Double { destinations.first?.distanceKm ?? 0 }
    /// Revenue for one full parcel on the primary destination.
    var payoutPerShipment: Money { destinations.first?.payoutPerParcel ?? 0 }
    /// Mass of one posted shipment. Named for the old single-parcel model.
    var shipmentMassKg: Int { parcelMassKg }
    /// Whole parcels posted per cycle across every destination.
    var parcelsPerCycle: Int {
        destinations.reduce(0) { total, destination in
            total + Self.parcelCount(
                volumeKg: cycleVolume(for: destination),
                parcelMassKg: parcelMassKg
            )
        }
    }
    /// Total revenue of one full cycle, all destinations included.
    var revenuePerCycle: Money {
        destinations.reduce(0) { total, destination in
            let volume = cycleVolume(for: destination)
            guard parcelMassKg > 0 else { return total }
            return total + Money(
                (Double(destination.payoutPerParcel) * Double(volume) / Double(parcelMassKg)).rounded()
            )
        }
    }
    var isMultiDrop: Bool { destinations.count > 1 }

    /// Lanes this agreement commits, by endpoint.
    var committedLaneIDs: [LaneID] { destinations.map(\.laneID) }

    /// Mass routed to one destination in a single cycle.
    func cycleVolume(for destination: ContractDestination) -> Int {
        Int(
            (Double(volumePerCycleKg) * Double(destination.shareBps)
                / Double(ContractDestination.fullShareBps)).rounded()
        )
    }

    static func parcelCount(volumeKg: Int, parcelMassKg: Int) -> Int {
        guard parcelMassKg > 0, volumeKg > 0 else { return 0 }
        return (volumeKg + parcelMassKg - 1) / parcelMassKg
    }
}

/// Open long-term lane available for signing.
struct ContractOffer: Codable, Identifiable, Sendable, ContractTerms {
    let id: ContractID
    let origin: CityID
    let productID: ProductID
    let archetype: ContractArchetype
    let destinations: [ContractDestination]
    /// Vehicle class used to size and price each parcel.
    let referenceVehicleTypeID: VehicleTypeID
    /// Mass of one posted parcel — sized to the reference vehicle.
    let parcelMassKg: Int
    /// Total mass moved per cycle. Bulk contracts exceed one vehicle by design.
    let volumePerCycleKg: Int
    /// How often a cycle of shipments is posted after signing.
    let shipmentIntervalMinutes: Int
    /// Time a posted parcel has before it counts as late.
    let deliveryWindowMinutes: Int
    /// Preparation time between signing and the first posted cycle.
    let leadTimeMinutes: Int
    /// Contract length in game days. Nil for evergreen contracts.
    let durationDays: Int?
    /// Pickup address in the origin city.
    let originFirmID: FirmID?
    let createdAt: GameTime
    let expiresAt: GameTime
}

/// Signed contract that periodically posts shipment obligations.
/// Each shipment must be delivered before its deadline or a penalty is charged.
struct ActiveContract: Codable, Identifiable, Sendable, ContractTerms {
    let id: ContractID
    let origin: CityID
    let productID: ProductID
    let archetype: ContractArchetype
    let destinations: [ContractDestination]
    let referenceVehicleTypeID: VehicleTypeID
    let parcelMassKg: Int
    let volumePerCycleKg: Int
    let shipmentIntervalMinutes: Int
    let deliveryWindowMinutes: Int
    let signedAt: GameTime
    /// Nil for evergreen contracts: they end only when cancelled.
    let endsAt: GameTime?
    var nextShipmentAt: GameTime
    var shipmentsIssued: Int
    var shipmentsCompleted: Int
    var shipmentsMissed: Int
    /// Total compensation charged for missed shipments.
    var penaltiesPaid: Money
    /// Safe close requested: no new cycles post, committed parcels still run.
    var cancellationRequestedAt: GameTime?
    let originFirmID: FirmID?

    var isEvergreen: Bool { endsAt == nil }

    /// True once the contract must stop posting new work.
    func isClosing(at clock: GameTime) -> Bool {
        if cancellationRequestedAt != nil { return true }
        if let endsAt { return endsAt <= clock }
        return false
    }
}

// MARK: - Routes

/// What a vehicle does at a route stop. The address is derived: shipment tasks
/// use the shipment's firm address, contract tasks the contract's firm address,
/// and plain travel targets the city itself.
