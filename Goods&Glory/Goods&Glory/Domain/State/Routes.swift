//
//  Routes.swift
//  Goods&Glory
//
//  Route value types: the itinerary, its stops and tasks, the runs that
//  execute it and the rolling record of how well it performs.
//

import Foundation

enum RouteTask: Codable, Hashable, Sendable {
    /// Drive here, nothing else. Allows free repositioning legs.
    case travel
    /// Claim waiting freight of this lane from the origin dock: parcels are
    /// minted from the lane's accrual, priced for the loading vehicle at the
    /// spot rate, until the vehicle is full. Waits when the dock is empty.
    case pickupLane(LaneID)
    /// Store every carried parcel that is not already at its final city into
    /// this city's warehouse. The backbone of consolidation.
    case dropToWarehouse
    /// Load parcels from this city's warehouse, earliest deadline first, until
    /// the vehicle is full. The lot narrows what may be loaded.
    case loadFromWarehouse(StorageLotKey)
    /// Unload every carried parcel whose final destination is this city and
    /// collect its payout. Makes one distribution run serve many customers.
    case deliverAll
    /// Drop the carried parcels of one specific lane — the product the player
    /// deliberately loaded earlier on the lap — either at the receiver firm
    /// (payout) or into this city's warehouse (consolidation). The pairing task
    /// for `pickupLane`: it turns a claimed product into a routed one, so the
    /// player decides per product exactly where it goes.
    case deliverLane(LaneID, LaneDropTarget)
}

/// Where a picked-up lane's cargo is handed over later on the lap. Pickup is
/// always at the origin firm's dock; this is the matching destination choice.
enum LaneDropTarget: Codable, Hashable, Sendable {
    /// Hand over at the lane's receiver firm and collect the payout. Valid only
    /// in the lane's destination city.
    case destination
    /// Store in this city's warehouse for a later leg or another route to
    /// finish. Valid in any city on the lap that has a warehouse.
    case warehouse
}

/// Groups warehouse cargo the way a dispatcher thinks about it: same product
/// and final destination. Shipments keep their own identity in the engine; the
/// lot is how the player selects and moves them in bulk.
struct StorageLotKey: Codable, Hashable, Sendable {
    let productID: ProductID
    let destinationCityID: CityID
}

/// Where a parcel physically is right now.
enum CargoLocation: Codable, Hashable, Sendable {
    /// Waiting at its pickup address in this city.
    case address(CityID)
    /// Loaded on a vehicle.
    case vehicle(VehicleID)
    /// Stored in a warehouse, available for any route to pick up.
    case warehouse(FacilityID)

    var vehicleID: VehicleID? {
        if case .vehicle(let id) = self { return id }
        return nil
    }

    var facilityID: FacilityID? {
        if case .warehouse(let id) = self { return id }
        return nil
    }
}

struct RouteStop: Codable, Hashable, Identifiable, Sendable {
    /// Deterministic runtime id so stops stay addressable while editing.
    let id: Int
    var cityID: CityID
    var task: RouteTask
}

/// Rolling operating record of one route across all its runs and vehicles.
/// The route dashboard reads it; the engine only ever adds. This is where
/// "how good is my line?" stops being a feeling and becomes a number.
struct RouteStats: Codable, Hashable, Sendable {
    /// How many completed game days feed the displayed $/day average.
    static let rollingDayCount = 3

    /// Kilometres driven with at least one parcel on board.
    var loadedKm: Double = 0
    /// Kilometres driven empty — the number the player learns to fight.
    var emptyKm: Double = 0
    var revenue: Money = 0
    var cost: Money = 0
    /// When the route first started running; day rates need at least one day.
    var firstStartedAt: GameTime?
    /// Net accrued during the open game day (not yet folded into the window).
    var dayNet: Money = 0
    /// Completed game days' net, oldest first. Caps at `rollingDayCount`.
    var recentDayNets: [Money] = []
    /// How full the route ran over its recent working days.
    var load = RollingLoadFactor()
    /// Game-day index (`clock.totalMinutes / minutesPerDay`) for `dayNet`.
    var dayIndex: Int? = nil

    var totalKm: Double { loadedKm + emptyKm }
    /// Share of driven distance that carried freight, 0...1. Nil before any leg.
    var loadedShare: Double? {
        totalKm > 0 ? loadedKm / totalKm : nil
    }
    var profit: Money { revenue - cost }

    /// How full the truck was through the time the route actually worked,
    /// averaged over the last few active days.
    ///
    /// Measured in minutes rather than kilometres on purpose: a route that
    /// shuttles a dock into the warehouse across town drives no distance at
    /// all, and a kilometre-based measure reports nothing for it. Minutes cover
    /// both — driving and standing on a dock are both the vehicle's day.
    ///
    /// `loadedShare` answers a weaker question — did the leg carry *anything* —
    /// so a lane running at 10% full still scores 100%.
    var recentLoadFactor: Double? { load.current }

    /// Trailing net per game day — average of up to the last three *completed*
    /// days. The open day is excluded on purpose: the number stays still while
    /// you plan, then steps once at midnight instead of ticking like a stock.
    func profitPerDay(at clock: GameTime) -> Money? {
        guard let firstStartedAt else { return nil }
        let minutes = firstStartedAt.minutes(until: clock)
        guard minutes >= GameState.minutesPerDay else { return nil }
        if !recentDayNets.isEmpty {
            let sum = recentDayNets.reduce(0, +)
            return Money((Double(sum) / Double(recentDayNets.count)).rounded())
        }
        // First day not closed yet (or a legacy save before the window existed):
        // fall back to the lifetime average once, then the rolling window takes over.
        return Money((Double(profit) * Double(GameState.minutesPerDay) / Double(minutes)).rounded())
    }

    /// Marks the route as operating from `clock` and opens today's bucket.
    mutating func markStarted(at clock: GameTime) {
        if firstStartedAt == nil {
            firstStartedAt = clock
        }
        if dayIndex == nil {
            dayIndex = clock.totalMinutes / GameState.minutesPerDay
        }
    }

    /// Folds closed days into the rolling window. Safe to call every advance.
    mutating func rollDays(to clock: GameTime) {
        let today = clock.totalMinutes / GameState.minutesPerDay
        // Legacy / mid-campaign saves: seed one synthetic day from the lifetime
        // average so the card is stable immediately instead of flickering for
        // another full day.
        if recentDayNets.isEmpty,
           dayIndex == nil,
           let firstStartedAt,
           firstStartedAt.minutes(until: clock) >= GameState.minutesPerDay {
            let lifetime = Money(
                (Double(profit) * Double(GameState.minutesPerDay)
                    / Double(firstStartedAt.minutes(until: clock))).rounded()
            )
            recentDayNets = [lifetime]
            dayIndex = today
            dayNet = 0
            return
        }
        guard let open = dayIndex else {
            dayIndex = today
            return
        }
        var day = open
        while day < today {
            recentDayNets.append(dayNet)
            if recentDayNets.count > Self.rollingDayCount {
                recentDayNets.removeFirst(recentDayNets.count - Self.rollingDayCount)
            }
            dayNet = 0
            day += 1
        }
        dayIndex = today
    }

    /// Records a stretch of work — a driven leg or a spell on a dock — for the
    /// trailing efficiency window.
    mutating func noteWork(minutes: Int, fill: Double, at clock: GameTime) {
        rollDays(to: clock)
        load.note(minutes: minutes, fill: fill, at: clock)
    }

    /// Attributes a revenue/cost change to the open day after rolling midnights.
    mutating func noteCashDelta(_ delta: Money, at clock: GameTime) {
        guard delta != 0 else {
            rollDays(to: clock)
            return
        }
        rollDays(to: clock)
        dayNet += delta
    }
}

/// A player-built vehicle itinerary that loops until stopped.
struct Route: Codable, Identifiable, Sendable {
    let id: RouteID
    var name: String
    var stops: [RouteStop]
    /// Vehicles serving this route.
    var vehicleIDs: [VehicleID]
    /// Running routes spawn runs for idle assigned vehicles and loop forever.
    var isRunning: Bool
    /// Set when deletion was requested while vehicles were still executing the
    /// route. The definition remains as a tombstone until every run safely
    /// winds down, then the engine purges it automatically.
    var cancellationRequestedAt: GameTime? = nil
    var stats: RouteStats = RouteStats()

    /// Lanes this route claims from — its baseline demand.
    var coveredLaneIDs: [LaneID] {
        stops.compactMap { stop in
            if case .pickupLane(let id) = stop.task { return id }
            return nil
        }
    }
}

/// An accepted parcel moving through the network. It outlives any single route:
/// a parcel may be picked up by one route, stored in a warehouse, then finished
/// by another. Removed only on final delivery.
struct Shipment: Codable, Identifiable, Sendable {
    /// Same id as the originating offer.
    let id: JobID
    /// Snapshot of the accepted offer (addresses, load, payout, deadline).
    let offer: JobOffer
    var location: CargoLocation
    /// The route that committed to carrying this parcel next. Nil means the
    /// parcel is free: it sits in a warehouse or address for anyone to take.
    var assignedRouteID: RouteID?
    /// Operating cost the current custodian has spent on this parcel since it
    /// picked it up. Cleared whenever the parcel is handed over.
    var carriedCost: Money = 0
    /// Payout already credited to earlier legs of this parcel's journey.
    /// The route that finally delivers books `payout - settledPayout`, so the
    /// journey pays exactly once however many routes shared it.
    var settledPayout: Money = 0

    /// Nil while the cargo is not on a vehicle. Kept for call-site clarity.
    var loadedVehicleID: VehicleID? { location.vehicleID }

    var lotKey: StorageLotKey {
        StorageLotKey(
            productID: offer.productID,
            destinationCityID: offer.destination
        )
    }

    /// True when this parcel can be handed over at the given city.
    func isDeliverable(at cityID: CityID) -> Bool {
        offer.destination == cityID
    }
}

/// A dispatcher-facing grouping of warehouse cargo. Derived on demand from
/// `Shipment` records; never stored, never saved.
struct StorageLot: Identifiable, Sendable {
    let key: StorageLotKey
    let facilityID: FacilityID
    /// Parcel ids ordered by deadline, then id — the order the engine loads in.
    let shipmentIDs: [JobID]
    let load: LoadSize
    let earliestDeadline: GameTime?
    /// Revenue still to be collected once these parcels reach their destination.
    let pendingPayout: Money

    var id: StorageLotKey { key }
    var parcelCount: Int { shipmentIDs.count }
}

enum RouteRunPhase: String, Codable, Sendable {
    /// Driving toward the current stop's city.
    case traveling
    /// Loading or unloading at the current stop.
    case servicing
    /// Parked at the stop during an idle lap guard.
    case waiting
}

/// One vehicle executing one route. Phases advance on the engine event loop.
struct RouteRun: Codable, Identifiable, Sendable {
    let id: Int
    let routeID: RouteID
    let vehicleID: VehicleID
    /// Index into the route's stops the run is heading to or working at.
    var stopIndex: Int
    var phase: RouteRunPhase
    var phaseStartedAt: GameTime
    var phaseEndsAt: GameTime
    /// City the current traveling leg started from (map interpolation).
    var legOriginCityID: CityID
    var legDistanceKm: Double
    /// When the current lap began; guards against zero-time idle loops.
    var lapStartedAt: GameTime
    /// Parcels claimed at service start, loaded at service end. A list, not a
    /// single id: one dock visit fills the vehicle rather than taking one box.
    var claimedShipmentIDs: [JobID]
    /// Wind-down: skip pickups, finish deliveries, then release the vehicle.
    var isWindingDown: Bool
}
