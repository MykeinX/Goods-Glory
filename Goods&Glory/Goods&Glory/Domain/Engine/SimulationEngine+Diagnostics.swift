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
//     verdict — starved routes and stalled docks —
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
        out.append(contentsOf: section("cities", cityLines(state: state)))
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

    // MARK: Headline

    private func headline(state: GameState) -> String {
        let net = state.stats.totalRevenue - state.stats.totalCost
        return "d\(day(state.clock)) cash \(money(state.cash)) · fleet \(state.vehicles.count)"
            + " · routes \(state.routes.count) · sites \(state.facilities.count)"
            + " · delivered \(state.stats.deliveredJobs)"
            + " · lifetime rev \(money(state.stats.totalRevenue)) cost \(money(state.stats.totalCost))"
            + " net \(money(net))"
    }

    // MARK: Verdicts

    /// What is wrong, worst first. Everything below in the report is evidence
    /// for these lines.
    private func problems(state: GameState) -> [String] {
        var lines: [String] = []

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

        let overview = OperationsOverview.make(state: state, catalog: catalog)
        for city in overview.cities {
            if city.isStalled {
                lines.append("!  \(short(city.cityID)): \(kg(city.waitingKg)) waiting,"
                    + " no truck here or inbound")
            }
        }

        return lines.isEmpty ? ["none detected"] : lines
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

    /// Short, unambiguous name for a stop's work.
    private func taskTag(_ task: RouteTask) -> String {
        switch task {
        case .travel: "travel"
        // Never abbreviated: two lanes out of one city can share a long prefix
        // ("us_houston.industrial_parts" vs "…industrial_chemicals"), and a
        // truncated id can make a route look like it works a different lane.
        // A wide line beats a wrong one.
        case .pickupLane(let id): "takeLane(\(id.rawValue))"
        case .deliverLane(_, let target): target == .warehouse ? "laneToStore" : "laneToFirm"
        case .dropToWarehouse: "store"
        case .loadFromWarehouse: "collect"
        case .deliverAll: "dropAll"
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
