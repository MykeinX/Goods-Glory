//
//  RouteBuilderView+Planning.swift
//  Goods&Glory
//
//  Planning logic behind the builder: what is editable, what a lap adds
//  up to, what is wrong with it, and how commands are issued.
//

import SwiftUI

extension RouteBuilderView {
    func canEdit(_ route: Route) -> Bool {
        guard let state = session.state else { return false }
        return !route.isRunning
            && route.cancellationRequestedAt == nil
            && state.routeRuns(of: route.id).isEmpty
    }

    func canAppend(_ route: Route) -> Bool {
        route.cancellationRequestedAt == nil && !isWindingDown(route)
    }

    func isWindingDown(_ route: Route) -> Bool {
        guard let state = session.state else { return false }
        return !route.isRunning && !state.routeRuns(of: route.id).isEmpty
    }

    func routeStatus(_ route: Route) -> (text: String, color: Color) {
        if route.cancellationRequestedAt != nil { return ("Cancelling", Theme.coral) }
        if route.isRunning { return ("Running", Theme.mint) }
        if isWindingDown(route) { return ("Finishing Freight", Theme.warning) }
        return ("Draft", Theme.textSecondary)
    }

    func cityVisits(_ route: Route) -> [CityVisit] {
        route.stops.reduce(into: []) { visits, stop in
            if let last = visits.indices.last, visits[last].cityID == stop.cityID {
                visits[last].stops.append(stop)
            } else {
                visits.append(CityVisit(id: stop.id, cityID: stop.cityID, stops: [stop]))
            }
        }
    }

    func dropVisit(
        _ draggedID: Int,
        on targetID: Int,
        placeAfter: Bool,
        route: Route
    ) {
        var visits = cityVisits(route)
        guard let source = visits.firstIndex(where: { $0.id == draggedID }),
              let target = visits.firstIndex(where: { $0.id == targetID }) else { return }
        let moved = visits.remove(at: source)
        var insertion = target
        if source < target { insertion -= 1 }
        if placeAfter { insertion += 1 }
        visits.insert(moved, at: min(max(0, insertion), visits.count))
        apply(.reorderRouteVisits(routeID: route.id, orderedVisitIDs: visits.map(\.id)))
    }

    func moveVisit(_ id: Int, by offset: Int, route: Route) {
        guard canEdit(route) else { return }
        var visits = cityVisits(route)
        guard let source = visits.firstIndex(where: { $0.id == id }) else { return }
        let destination = source + offset
        guard visits.indices.contains(destination) else { return }
        visits.swapAt(source, destination)
        apply(.reorderRouteVisits(routeID: route.id, orderedVisitIDs: visits.map(\.id)))
    }

    func taskCount(_ route: Route) -> Int {
        route.stops.count { !isTravel($0.task) }
    }

    func isTravel(_ task: RouteTask) -> Bool {
        if case .travel = task { return true }
        return false

    }

    func taskChipText(_ task: RouteTask) -> String {
        switch task {
        case .travel:
            return "Drive"
        case .pickupLane(let laneID):
            if let lane = session.catalog.lane(laneID),
               let firm = session.catalog.firm(lane.originFirmID) {
                return "PICK UP · \(firm.name)"
            }
            return "PICK UP FLOW FREIGHT"
        case .pickupContract(let contractID):
            return "PICK UP · \(contractFirm(contractID, pickup: true))"
        case .deliverContract(let contractID):
            return "DELIVER · \(contractFirm(contractID, pickup: false))"
        case .pickupShipment:
            return "ONE-OFF PICKUP"
        case .deliverShipment:
            return "ONE-OFF DELIVERY"
        case .dropToWarehouse:
            return "STORE IN WAREHOUSE"
        case .loadFromWarehouse(let lotKey):
            let product = session.catalog.product(lotKey.productID)?.name ?? lotKey.productID.rawValue
            return "LOAD · \(product) → \(session.cityName(lotKey.destinationCityID))"
        case .deliverAll:
            return "DELIVER EVERYTHING FOR THIS CITY"
        case .deliverLane(let laneID, let target):
            let lane = session.catalog.lane(laneID)
            switch target {
            case .destination:
                if let firmID = lane?.destinationFirmID,
                   let firm = session.catalog.firm(firmID) {
                    return "DELIVER · \(firm.name)"
                }
                return "DELIVER FLOW FREIGHT"
            case .warehouse:
                let product = lane.flatMap { session.catalog.product($0.productID)?.name } ?? "Freight"
                return "STORE · \(product)"
            }
        }
    }

    func contractFirm(_ contractID: ContractID, pickup: Bool) -> String {
        guard let contract = session.state?.activeContract(contractID) else { return "Ended contract" }
        let firmID = pickup ? contract.originFirmID : contract.destinationFirmID
        return firmID.flatMap(session.catalog.firm)?.name ?? session.cityName(pickup ? contract.origin : contract.destination)
    }



    func planningIssue(_ route: Route) -> String? {
        if route.stops.isEmpty { return "Add at least one city." }
        if assignedVehicles.isEmpty { return "Assign a vehicle before starting." }
        let contractTasks = route.stops.compactMap { stop -> (ContractID, Bool)? in
            switch stop.task {
            case .pickupContract(let id): return (id, true)
            case .deliverContract(let id): return (id, false)
            default: return nil
            }
        }
        // A warehouse drop or a catch-all delivery is a valid hand-off too:
        // collection routes legitimately end at a hub instead of a customer.
        let hasHandoff = route.stops.contains {
            switch $0.task {
            case .dropToWarehouse, .deliverAll, .deliverLane: return true
            default: return false
            }
        }
        if !hasHandoff {
            for id in Set(contractTasks.map(\.0)) {
                let entries = contractTasks.filter { $0.0 == id }
                if entries.contains(where: { $0.1 }), !entries.contains(where: { !$0.1 }) {
                    return "Cargo picked up here has nowhere to go — add a delivery, a warehouse drop, or 'deliver everything'."
                }
            }
        }
        return nil
    }

    func primaryActionTitle(_ route: Route) -> String {
        if route.cancellationRequestedAt != nil { return "Cancelling Route" }
        if route.isRunning { return "Stop Route" }
        if isWindingDown(route) { return "Finishing Freight" }
        if assignedVehicles.isEmpty { return "Assign Vehicle" }
        return "Start Route"
    }

    func primaryActionSymbol(_ route: Route) -> String {
        if route.cancellationRequestedAt != nil { return "hourglass" }
        if route.isRunning { return "stop.fill" }
        if isWindingDown(route) { return "clock.fill" }
        if assignedVehicles.isEmpty { return "truck.box.badge.plus" }
        return "play.fill"
    }

    func primaryActionDisabled(_ route: Route) -> Bool {
        route.cancellationRequestedAt != nil
            || isWindingDown(route)
            || (!route.isRunning && assignedVehicles.isEmpty == false && planningIssue(route) != nil)
    }

    func primaryAction(_ route: Route) {
        if route.isRunning {
            apply(.stopRoute(route.id))
        } else if assignedVehicles.isEmpty {
            showsVehiclePicker = true
        } else {
            apply(.startRoute(route.id))
        }
    }

    func destructiveRouteActionTitle(_ route: Route) -> String {
        if route.isRunning || isWindingDown(route) {
            return String(localized: "Cancel Route")
        }
        return String(localized: "Delete Route")
    }

    /// Cheap fingerprint so chrome UI can redraw without rebuilding corridors.
    var mapSnapshotDependency: Int {
        guard let state = session.state, let route = state.route(routeID) else { return 0 }
        var hasher = Hasher()
        hasher.combine(state.clock.totalMinutes)
        hasher.combine(route.id.rawValue)
        hasher.combine(route.name)
        hasher.combine(route.isRunning)
        hasher.combine(route.cancellationRequestedAt?.totalMinutes)
        hasher.combine(route.vehicleIDs.map(\.rawValue))
        for stop in route.stops {
            hasher.combine(stop.id)
            hasher.combine(stop.cityID.rawValue)
            hasher.combine(String(describing: stop.task))
        }
        hasher.combine(state.vehicles.count)
        hasher.combine(state.routeRuns.count)
        hasher.combine(state.activeJobs.count)
        return hasher.finalize()
    }

    func syncMapSnapshot() {
        guard let state = session.state, let route = state.route(routeID) else {
            mapSnapshot = .empty
            return
        }
        mapSnapshot = MapSceneAdapter.snapshot(
            state: state,
            catalog: session.catalog,
            projection: MapProjection(),
            previewRoute: route
        )
    }

    func clearMapSelection() {
        pendingCityID = nil
        mapSelection = .none
    }

    func apply(_ command: GameCommand) {
        if let error = session.perform(command) {
            commandError = error
        }
    }

    /// The one place a rejected command turns into a sentence lives in
    /// `CommandErrorMessage`. This screen used to keep its own copy of the
    /// switch, which meant every new command error had to be remembered twice —
    /// and the second copy was the one that fell behind.
    var commandErrorMessage: LocalizedStringKey {
        CommandErrorMessage.text(commandError)
    }
}
