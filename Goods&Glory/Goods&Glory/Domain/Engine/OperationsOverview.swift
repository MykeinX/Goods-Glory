//
//  OperationsOverview.swift
//  Goods&Glory
//
//  The running operation seen as a network rather than as a list of vehicles.
//  A per-vehicle list grows with the fleet and changes every tick, so past a
//  handful of trucks it stops being readable; the questions that survive scale
//  are per city — what is piling up here, what is coming, who is working it.
//
//  Scope is the company, not the world. Only cities the company has freight,
//  a building or a truck in get a row: the catalog accrues lane freight in
//  every city whether it is served or not, and counting that would list the
//  whole map and walk the entire lane table on every recompute.
//
//  Built in one pass over state so it can be recomputed while the tab is open.
//

import Foundation

/// One city's share of the running operation.
struct CityOperations: Identifiable, Equatable, Sendable {
    let cityID: CityID
    var id: CityID { cityID }

    /// Parcels the company already owes out of this city and has not collected.
    var waitingKg: Int = 0
    var waitingParcels: Int = 0
    /// Unclaimed lane freight piling up at this city's dock. Only counted where
    /// the company has a building; untouched markets stay outside its overview.
    var dockKg: Int = 0
    /// Freight picked up here and currently riding on a vehicle.
    var outboundKg: Int = 0
    /// Freight on a vehicle whose final destination is this city.
    var inboundKg: Int = 0
    var inboundParcels: Int = 0
    /// Freight resting in this city's warehouse between legs.
    var storedKg: Int = 0
    /// Trucks standing in this city right now, loading or idle.
    var vehiclesHere: Int = 0
    var idleHere: Int = 0
    /// Trucks whose current leg ends in this city.
    var vehiclesInbound: Int = 0
    /// Running routes that call here. A truck is only ever *at* a city for the
    /// minutes it is loading, so counting trucks alone made a well-served city
    /// flash "no truck" every time one pulled away. A route calling here is the
    /// stable fact; the truck count is the moment.
    var routesServing: Int = 0
    /// Minutes until the first of those legs finishes.
    var nextArrivalMinutes: Int?
    /// Share of the tightest delivery window already spent on freight sitting
    /// here, 0...1. Above `urgentThreshold` the city is running out of time.
    var urgency: Double = 0

    static let urgentThreshold: Double = 0.75

    /// Freight is piling up and nothing is set up to collect it.
    ///
    /// A route calling here counts as cover even with no truck standing on the
    /// dock this minute: the alarm is about the network being wrong, not about
    /// where a truck happens to be when the player opens the screen.
    var isStalled: Bool {
        waitingKg > 0 && vehiclesHere == 0 && vehiclesInbound == 0 && routesServing == 0
    }

    var isUrgent: Bool { waitingKg > 0 && urgency >= Self.urgentThreshold }

    /// Nothing waiting, nothing moving, nobody parked — not worth a row.
    var isQuiet: Bool {
        waitingKg == 0 && inboundKg == 0 && outboundKg == 0 && storedKg == 0
            && dockKg == 0 && vehiclesHere == 0 && vehiclesInbound == 0 && routesServing == 0
    }

    /// Ranking weight: tonnage the city is responsible for either way.
    var throughputKg: Int { waitingKg + inboundKg + outboundKg + storedKg + dockKg }
}

struct OperationsOverview: Equatable, Sendable {
    /// Only cities the company is actually working, biggest tonnage first.
    let cities: [CityOperations]
    let idleVehicles: Int
    let movingVehicles: Int
    let servicingVehicles: Int
    /// Tonnage riding on vehicles right now.
    let inTransitKg: Int
    /// Tonnage waiting for a truck across the network.
    let waitingKg: Int
    /// Payout riding on cargo currently loaded.
    let payoutOnBoard: Money

    static let empty = OperationsOverview(
        cities: [],
        idleVehicles: 0,
        movingVehicles: 0,
        servicingVehicles: 0,
        inTransitKg: 0,
        waitingKg: 0,
        payoutOnBoard: 0
    )

    static func make(state: GameState, catalog: GameCatalog) -> OperationsOverview {
        var builder = Builder(state: state, catalog: catalog)
        builder.collectStoredFreight()
        builder.collectVehicles()
        builder.collectDockFreight()
        builder.collectRouteCoverage()
        return builder.finish()
    }
}

/// Accumulator for `OperationsOverview.make`. A struct with named steps rather
/// than one 200-line function, so each source of freight stays legible.
private struct Builder {
    let state: GameState
    let catalog: GameCatalog

    var cities: [CityID: CityOperations] = [:]
    var idleVehicles = 0
    var movingVehicles = 0
    var servicingVehicles = 0
    var inTransitKg = 0
    var payoutOnBoard: Money = 0

    subscript(cityID: CityID) -> CityOperations {
        get { cities[cityID] ?? CityOperations(cityID: cityID) }
        set { cities[cityID] = newValue }
    }

    /// Tightest deadline pressure wins: a city is as urgent as its worst parcel.
    mutating func noteUrgency(_ cityID: CityID, offer: JobOffer) {
        let window = max(1, offer.createdAt.minutes(until: offer.expiresAt))
        let spent = Double(offer.createdAt.minutes(until: state.clock)) / Double(window)
        var entry = self[cityID]
        entry.urgency = max(entry.urgency, min(1, max(0, spent)))
        self[cityID] = entry
    }

    // MARK: Waiting at the dock

    /// Lane freight never posts an offer — it accrues at the dock until a truck
    /// is sent. It accrues in *every* city in the world though, served or not,
    /// so only the docks the company actually has a building at are its
    /// business. Listing every market would fill the screen with cities the
    /// player has never touched.
    ///
    /// Walking our few facilities and asking for their lanes also keeps this
    /// off the catalog-wide lane table, which is the expensive shape.
    mutating func collectDockFreight() {
        guard !state.facilities.isEmpty else { return }
        var seen: Set<CityID> = []
        for facility in state.facilities {
            guard seen.insert(facility.cityID).inserted else { continue }
            var dockKg = 0
            for lane in catalog.lanes(from: facility.cityID) {
                dockKg += state.laneAccrualKg[lane.id] ?? 0
            }
            guard dockKg > 0 else { continue }
            var entry = self[facility.cityID]
            entry.dockKg += dockKg
            self[facility.cityID] = entry
        }
    }

    // MARK: Resting in a warehouse

    mutating func collectStoredFreight() {
        guard !state.shipments.isEmpty else { return }
        var cityByFacility: [FacilityID: CityID] = [:]
        cityByFacility.reserveCapacity(state.facilities.count)
        for facility in state.facilities { cityByFacility[facility.id] = facility.cityID }

        for shipment in state.shipments {
            switch shipment.location {
            case .warehouse(let facilityID):
                guard let cityID = cityByFacility[facilityID] else { continue }
                var entry = self[cityID]
                entry.storedKg += shipment.offer.load.massKg
                self[cityID] = entry
                noteUrgency(cityID, offer: shipment.offer)
            case .vehicle:
                noteOnBoard(shipment.offer)
            case .address(let cityID):
                // Committed to a route but not yet collected: still waiting.
                var entry = self[cityID]
                entry.waitingKg += shipment.offer.load.massKg
                entry.waitingParcels += 1
                self[cityID] = entry
                noteUrgency(cityID, offer: shipment.offer)
            }
        }
    }

    /// Cargo on a vehicle counts against the city that loaded it and the city
    /// expecting it — the two halves of "what is moving through here".
    mutating func noteOnBoard(_ offer: JobOffer) {
        inTransitKg += offer.load.massKg
        payoutOnBoard += offer.payout

        var origin = self[offer.origin]
        origin.outboundKg += offer.load.massKg
        self[offer.origin] = origin

        var destination = self[offer.destination]
        destination.inboundKg += offer.load.massKg
        destination.inboundParcels += 1
        self[offer.destination] = destination
    }

    /// Which cities are on somebody's lap. Standing cover, as opposed to the
    /// truck that happens to be parked there this minute.
    mutating func collectRouteCoverage() {
        for route in state.routes where route.isRunning {
            for cityID in Set(route.stops.map(\.cityID)) {
                var entry = self[cityID]
                entry.routesServing += 1
                self[cityID] = entry
            }
        }
    }

    // MARK: Where the trucks are

    mutating func collectVehicles() {
        var runByVehicle: [VehicleID: RouteRun] = [:]
        runByVehicle.reserveCapacity(state.routeRuns.count)
        for run in state.routeRuns { runByVehicle[run.vehicleID] = run }

        for vehicle in state.vehicles {
            if let run = runByVehicle[vehicle.id] {
                collect(run: run, vehicle: vehicle)
            } else {
                idleVehicles += 1
                var entry = self[vehicle.cityID]
                entry.vehiclesHere += 1
                entry.idleHere += 1
                self[vehicle.cityID] = entry
            }
        }
    }

    private mutating func collect(run: RouteRun, vehicle: Vehicle) {
        switch run.phase {
        case .traveling:
            movingVehicles += 1
            let target = state.route(run.routeID)
                .flatMap { $0.stops.indices.contains(run.stopIndex) ? $0.stops[run.stopIndex] : nil }
                .map(\.cityID)
            if let target { arriving(at: target, in: run.phaseEndsAt) }
        case .servicing, .waiting:
            // A truck waiting at a dock for cargo is not idle — it cannot take
            // new work, and counting it as idle overstates free capacity.
            servicingVehicles += 1
            var entry = self[vehicle.cityID]
            entry.vehiclesHere += 1
            self[vehicle.cityID] = entry
        }
    }

    private mutating func arriving(at cityID: CityID, in endsAt: GameTime) {
        var entry = self[cityID]
        entry.vehiclesInbound += 1
        let minutes = max(0, state.clock.minutes(until: endsAt))
        entry.nextArrivalMinutes = min(entry.nextArrivalMinutes ?? .max, minutes)
        self[cityID] = entry
    }

    // MARK: Result

    /// Biggest first, and only that. Sorting trouble to the top made rows jump
    /// between ticks, which is the thing that made the old screen unreadable —
    /// trouble is a colour and a badge on the row instead.
    func finish() -> OperationsOverview {
        let rows = cities.values
            .filter { !$0.isQuiet }
            .sorted { left, right in
                if left.throughputKg != right.throughputKg {
                    return left.throughputKg > right.throughputKg
                }
                return left.cityID.rawValue < right.cityID.rawValue
            }
        return OperationsOverview(
            cities: rows,
            idleVehicles: idleVehicles,
            movingVehicles: movingVehicles,
            servicingVehicles: servicingVehicles,
            inTransitKg: inTransitKg,
            waitingKg: rows.reduce(0) { $0 + $1.waitingKg },
            payoutOnBoard: payoutOnBoard
        )
    }
}
