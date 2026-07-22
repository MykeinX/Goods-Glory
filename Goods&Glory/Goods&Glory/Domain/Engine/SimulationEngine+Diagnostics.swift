//
//  SimulationEngine+Diagnostics.swift
//  Goods&Glory
//
//  The campaign, written out so a problem can be found by reading rather than
//  by guessing. This is the artefact a play session produces when something is
//  wrong: it is meant to be copied out of the app whole and read cold, by
//  someone who was not there.
//
//  Two rules earn their keep here:
//
//  1. **Conclusions before data.** The `problems` section is the engine's own
//     verdict — uncovered contracts, starved routes, stalled docks —
//     so the reader starts from what is wrong, not from a wall of lines. Raw
//     sections below exist to check the verdict, not to replace it.
//  2. **Every number that has two definitions prints both.** A route's fill and
//     its empty distance are different measures, and the session where they
//     disagreed on screen ("55% loaded" beside "74% full") cost an evening.
//
//  Pure over state; records nothing, changes nothing.
//

import Foundation

extension SimulationEngine {
    func diagnosticReport(state: GameState) -> String {
        var out: [String] = []
        out.append("=== GOODS & GLORY DIAGNOSTIC ===")
        out.append(headline(state: state))
        out.append(contentsOf: section("problems", problems(state: state)))
        out.append(contentsOf: section("routes", routeLines(state: state)))
        out.append(contentsOf: section("contracts", contractLines(state: state)))
        out.append(contentsOf: section("cities", cityLines(state: state)))
        out.append(contentsOf: section("unlifted parcels", boardLines(state: state)))
        out.append(contentsOf: section("log", logLines(state: state)))
        return out.joined(separator: "\n")
    }

    private func section(_ title: String, _ lines: [String]) -> [String] {
        guard !lines.isEmpty else { return [] }
        return ["--- \(title) ---"] + lines
    }

    private func day(_ time: GameTime) -> Int {
        time.totalMinutes / GameState.minutesPerDay + 1
    }

    private func stamp(_ time: GameTime) -> String {
        let minuteOfDay = time.totalMinutes % GameState.minutesPerDay
        return String(format: "d%02d %02d:%02d", day(time), minuteOfDay / 60, minuteOfDay % 60)
    }

    private func hours(_ minutes: Int) -> String {
        minutes >= 1_440
            ? String(format: "%.1fd", Double(minutes) / 1_440)
            : "\(max(0, minutes) / 60)h"
    }

    // MARK: Headline

    private func headline(state: GameState) -> String {
        let net = state.stats.totalRevenue - state.stats.totalCost
        return "d\(day(state.clock)) cash \(money(state.cash)) · fleet \(state.vehicles.count)"
            + " · routes \(state.routes.count) · sites \(state.facilities.count)"
            + " · contracts \(state.activeContracts.count)"
            + " · delivered \(state.stats.deliveredJobs)"
            + " · lifetime rev \(money(state.stats.totalRevenue)) cost \(money(state.stats.totalCost))"
            + " net \(money(net))"
    }

    // MARK: Verdicts

    /// What is wrong, worst first. Everything below in the report is evidence
    /// for these lines.
    private func problems(state: GameState) -> [String] {
        var lines: [String] = []

        for contract in state.activeContracts {
            let coverage = coverage(of: contract, state: state)
            let carriers = state.routes
                .filter { $0.coveredContractIDs.contains(contract.id) || servesLanes(of: contract, route: $0) }
                .map { "r\($0.id.rawValue)" }
            switch coverage {
            case .uncovered(let waiting):
                lines.append("!! c\(contract.id.rawValue) \(short(contract.origin))"
                    + "→\(short(contract.destination)): \(waiting) parcel(s) with nothing carrying them"
                    + (carriers.isEmpty
                       ? " · no route works this lane"
                       : " · routes on the lane: \(carriers.joined(separator: ","))"))
            case .partial(_, let waiting):
                lines.append("!  c\(contract.id.rawValue) \(short(contract.origin))"
                    + "→\(short(contract.destination)): \(waiting) parcel(s) still unclaimed"
                    + " · carried by \(carriers.joined(separator: ","))")
            case .notStarted, .covered:
                break
            }
            if contract.shipmentsMissed > 0 {
                lines.append("!! c\(contract.id.rawValue) missed \(contract.shipmentsMissed)"
                    + " of \(contract.shipmentsIssued) issued — cadence outruns the route")
            }
        }

        for route in state.routes {
            switch bottleneck(of: route, state: state) {
            case .noVehicle:
                lines.append("!! r\(route.id.rawValue) \(route.name): no vehicle assigned")
            case .moreFreightThanCapacity(let waitingKg):
                lines.append("!  r\(route.id.rawValue) \(route.name): \(kg(waitingKg)) beyond one lap's capacity")
            case .underloaded(let percent):
                lines.append("·  r\(route.id.rawValue) \(route.name): trucks run \(percent)% full")
            case .emptyReturn(let percent):
                lines.append("·  r\(route.id.rawValue) \(route.name): \(percent)% of driven km carries nothing")
            case .healthy:
                break
            }
            if let perDay = route.stats.profitPerDay(at: state.clock), perDay < 0 {
                lines.append("!! r\(route.id.rawValue) \(route.name): losing \(money(-perDay))/day")
            }
        }

        // Have the contracts outgrown the fleet? Each card reads "123% of a
        // truck" on its own; three of them add up to trucks nobody bought.
        let committed = committedKgPerDay(state: state)
        if committed > 0 {
            let laneKm = state.activeContracts
                .flatMap { $0.destinations.map(\.distanceKm) }
                .max() ?? 0
            let capacity = fleetKgPerDay(state: state, laneDistanceKm: laneKm)
            if capacity > 0, committed > capacity {
                lines.append("!! commitments \(kg(committed))/d exceed the whole fleet's"
                    + " \(kg(capacity))/d on this lane — some contract must miss")
            } else if capacity > 0 {
                lines.append("·  commitments \(kg(committed))/d of a fleet that moves"
                    + " \(kg(capacity))/d, spot freight included")
            }
        }

        let overview = OperationsOverview.make(state: state, catalog: catalog)
        for city in overview.cities {
            if city.isStalled {
                lines.append("!  \(short(city.cityID)): \(kg(city.waitingKg)) waiting,"
                    + " no truck here or inbound")
            }
        }

        return lines.isEmpty ? ["none detected"] : lines
    }

    private func servesLanes(of contract: ActiveContract, route: Route) -> Bool {
        let lanes = Set(route.coveredLaneIDs)
        return contract.destinations.contains { lanes.contains($0.laneID) }
    }

    // MARK: Routes

    private func routeLines(state: GameState) -> [String] {
        state.routes.flatMap { route -> [String] in
            let stats = route.stats
            // Both measures, always: one says how full, the other says how much
            // of the driving was unpaid. They are not interchangeable.
            let fill = stats.recentLoadFactor.map { "fill \(pct($0))" } ?? "fill —"
            let emptyShare = stats.totalKm > 0 ? stats.emptyKm / stats.totalKm : 0
            let perDay = stats.profitPerDay(at: state.clock).map { money($0) + "/d" } ?? "—"
            let head = "r\(route.id.rawValue) \(route.name)"
                + " · \(route.isRunning ? "running" : "stopped")"
                + " · veh \(route.vehicleIDs.count)"
                + " · \(fill) · empty \(pct(emptyShare))"
                + " · \(km(stats.loadedKm))/\(km(stats.emptyKm)) loaded/empty"
                + " · rev \(money(stats.revenue)) cost \(money(stats.cost)) \(perDay)"
            let stops = route.stops
                .map { "\(short($0.cityID)):\(taskTag($0.task))" }
                .joined(separator: " > ")
            // Per truck, so a fleet where one vehicle drags the average down is
            // visible instead of hidden inside the route's number.
            let crew = route.vehicleIDs
                .compactMap { state.vehicle($0) }
                .map { vehicle in
                    "v\(vehicle.id.rawValue) "
                        + (vehicle.load.current.map { pct($0) } ?? "—")
                }
                .joined(separator: " · ")
            return [
                head,
                "    stops \(stops.isEmpty ? "none" : stops)",
                "    crew fill \(crew.isEmpty ? "none" : crew)"
            ]
        }
    }

    /// Short, unambiguous name for a stop's job. The route list is unreadable
    /// without knowing *what* each stop does, which is the difference between
    /// "why is my contract uncovered" and "ah, no pickup for it".
    private func taskTag(_ task: RouteTask) -> String {
        switch task {
        case .travel: "travel"
        // Never abbreviated: two lanes out of one city can share a long prefix
        // ("us_houston.industrial_parts" vs "…industrial_chemicals"), and a
        // truncated id made a contract look covered by a route that in fact
        // worked a different lane. A wide line beats a wrong one.
        case .pickupLane(let id): "takeLane(\(id.rawValue))"
        case .deliverLane(_, let target): target == .warehouse ? "laneToStore" : "laneToFirm"
        case .pickupContract(let id): "takeContract(c\(id.rawValue))"
        case .deliverContract(let id): "dropContract(c\(id.rawValue))"
        case .pickupShipment(let id): "takeParcel(j\(id.rawValue))"
        case .deliverShipment(let id): "dropParcel(j\(id.rawValue))"
        case .dropToWarehouse: "store"
        case .loadFromWarehouse: "collect"
        case .deliverAll: "dropAll"
        }
    }

    // MARK: Contracts

    private func contractLines(state: GameState) -> [String] {
        state.activeContracts.map { contract in
            let shares = contract.destinations
                .map { "\(short($0.cityID)) \($0.committedShareBps / 100)%" }
                .joined(separator: "+")
            let verdict: String = switch coverage(of: contract, state: state) {
            case .notStarted(let minutes): "starts in \(hours(minutes))"
            case .covered: "covered"
            case .partial(let moving, let waiting): "partial \(moving) moving / \(waiting) waiting"
            case .uncovered(let waiting): "UNCOVERED \(waiting) waiting"
            }
            let lanes = contract.destinations
                .map { destination -> String in
                    // How deep the relationship on this lane is, since that is
                    // now what decides which offers appear and how big they get.
                    let served = catalog.lane(destination.laneID)
                        .map { servedShareBps(of: $0, state: state) / 100 } ?? 0
                    return "\(destination.laneID.rawValue) (you haul \(served)%)"
                }
                .joined(separator: ",")
            return "c\(contract.id.rawValue) \(short(contract.origin))→\(shares)"
                + " · lane \(lanes)"
                + " · every \(hours(contract.shipmentIntervalMinutes))"
                + " · \(kg(contract.parcelMassKg)) parcels"
                + " · issued \(contract.shipmentsIssued) done \(contract.shipmentsCompleted)"
                + " missed \(contract.shipmentsMissed)"
                + " · next in \(hours(state.clock.minutes(until: contract.nextShipmentAt)))"
                + " · \(verdict)"
        }
    }

    // MARK: Cities

    private func cityLines(state: GameState) -> [String] {
        let overview = OperationsOverview.make(state: state, catalog: catalog)
        return overview.cities.map { city in
            return "\(short(city.cityID))"
                + " · dock \(kg(city.dockKg)) · booked out \(kg(city.waitingKg))"
                + " (\(city.waitingParcels) parcel(s))"
                + " · inbound \(kg(city.inboundKg)) · stored \(kg(city.storedKg))"
                + " · trucks \(city.vehiclesHere) here/\(city.vehiclesInbound) coming"
        }
    }

    // MARK: The board

    /// Parcels posted and not yet lifted by anybody. An empty section here is
    /// the healthy state; a long one is the whole story.
    private func boardLines(state: GameState) -> [String] {
        state.offers
            .sorted { ($0.expiresAt, $0.id.rawValue) < ($1.expiresAt, $1.id.rawValue) }
            .prefix(20)
            .map { offer in
                let age = offer.createdAt.minutes(until: state.clock)
                let left = state.clock.minutes(until: offer.expiresAt)
                // The decisive question for an unlifted parcel is who was
                // supposed to take it, so the report answers it here rather
                // than leaving it to be reconstructed from the route list.
                let carriers = state.routes.filter { route in
                    guard route.isRunning else { return false }
                    if let laneID = offer.laneID, route.coveredLaneIDs.contains(laneID) {
                        return true
                    }
                    return offer.contractID.map { route.coveredContractIDs.contains($0) } ?? false
                }
                let verdict = carriers.isEmpty
                    ? "NO ROUTE WORKS THIS LANE"
                    : "on \(carriers.map { "r\($0.id.rawValue)" }.joined(separator: ","))"
                return "j\(offer.id.rawValue) \(short(offer.origin))→\(short(offer.destination))"
                    + " \(kg(offer.load.massKg)) \(money(offer.payout))"
                    + " · \(offer.source == .contract ? "contract c\(offer.contractID?.rawValue ?? 0)" : "lane")"
                    + " · lane \(offer.laneID?.rawValue ?? "—")"
                    + " · \(verdict)"
                    + " · waiting \(hours(age)) · due in \(hours(left))"
            }
    }

    // MARK: Money lines

    private func logLines(state: GameState) -> [String] {
        state.debug.entries.map { entry in
            let delta = entry.delta == 0
                ? ""
                : (entry.delta > 0 ? " +\(entry.delta)" : " \(entry.delta)")
            return "\(stamp(entry.at)) \(entry.detail)\(delta) [\(money(entry.cash))]"
        }
    }
}
