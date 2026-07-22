//
//  SimulationEngine+Routes.swift
//  Goods&Glory
//
//  Route editing commands: stops, visits, tasks, vehicles, lifecycle.
//  The runner that executes these routes lives in +RouteRunner.
//

import Foundation

extension SimulationEngine {
    // MARK: - Route commands

    func createRoute(name: String, state: inout GameState) {
        let resolved = name.isEmpty ? "Route \(state.routes.count + 1)" : name
        state.routes.append(Route(
            id: RouteID(rawValue: state.issueID()),
            name: resolved,
            stops: [],
            vehicleIDs: [],
            isRunning: false
        ))
    }

    func renameRoute(_ routeID: RouteID, name: String, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        guard !name.isEmpty else { return }
        state.routes[index].name = name
    }

    func addTravelStop(routeID: RouteID, cityID: CityID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }),
              catalog.city(cityID) != nil else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        // Appending never disturbs running stop indices, so it is always allowed.
        state.routes[index].stops.append(
            RouteStop(id: state.issueID(), cityID: cityID, task: .travel)
        )
    }

    /// Structural edits require a fully stopped route (no runs referencing indices).
    func editableRouteIndex(_ routeID: RouteID, state: GameState) throws -> Int {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil,
              !state.routes[index].isRunning,
              state.routeRuns(of: routeID).isEmpty else {
            throw CommandError.routeIsRunning
        }
        return index
    }

    /// Adding work is allowed even while a route runs: a live vehicle simply
    /// picks up the new stop on its lap. Only a route being wound down or
    /// cancelled is off limits, because its runs are meant to shrink, not grow.
    func insertableRouteIndex(_ routeID: RouteID, state: GameState) throws -> Int {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil,
              state.routes[index].isRunning || state.routeRuns(of: routeID).isEmpty else {
            throw CommandError.routeIsRunning
        }
        return index
    }

    /// Inserts a stop and keeps every live run pointing at the same logical
    /// stop by shifting the indices that sit at or after the insertion point.
    /// This is what makes editing a running route safe.
    func insertRouteStop(_ stop: RouteStop, at index: Int, routeIndex: Int, state: inout GameState) {
        let routeID = state.routes[routeIndex].id
        state.routes[routeIndex].stops.insert(stop, at: index)
        for runIndex in state.routeRuns.indices
        where state.routeRuns[runIndex].routeID == routeID
            && state.routeRuns[runIndex].stopIndex >= index {
            state.routeRuns[runIndex].stopIndex += 1
        }
    }

    func removeRouteStop(routeID: RouteID, stopID: Int, state: inout GameState) throws {
        let index = try editableRouteIndex(routeID, state: state)
        guard let stop = state.routes[index].stops.first(where: { $0.id == stopID }) else {
            throw CommandError.unknownReference
        }
        switch stop.task {
        case .pickupShipment(let jobID), .deliverShipment(let jobID):
            // Shipment stops travel in pairs; go through the job detach path.
            try removeJobFromRoute(jobID: jobID, routeID: routeID, state: &state)
        case .pickupLane(let laneID):
            state.routes[index].stops.removeAll { $0.id == stopID }
            // Pickup created the matching deliverLane(s); drop them too so a
            // Boston "deliver X" does not outlive a deleted Las Vegas pickup.
            purgeOrphanedLaneDeliveries(
                routeIndex: index,
                candidateLaneIDs: [laneID],
                state: &state
            )
        case .travel, .pickupContract, .deliverContract,
             .dropToWarehouse, .loadFromWarehouse, .deliverAll, .deliverLane:
            // Standing instructions with no cargo bookkeeping of their own.
            state.routes[index].stops.removeAll { $0.id == stopID }
        }
    }

    /// Removes `deliverLane` stops for lanes that no longer have a `pickupLane`
    /// on this route. Cities stay; only the orphaned drop instructions go.
    func purgeOrphanedLaneDeliveries(
        routeIndex: Int,
        candidateLaneIDs: Set<LaneID>,
        state: inout GameState
    ) {
        guard !candidateLaneIDs.isEmpty else { return }
        let stillPickedUp = Set(state.routes[routeIndex].stops.compactMap { stop -> LaneID? in
            if case .pickupLane(let id) = stop.task { return id }
            return nil
        })
        let orphaned = candidateLaneIDs.subtracting(stillPickedUp)
        guard !orphaned.isEmpty else { return }
        state.routes[routeIndex].stops.removeAll { stop in
            if case .deliverLane(let id, _) = stop.task {
                return orphaned.contains(id)
            }
            return false
        }
    }

    func moveRouteStop(routeID: RouteID, stopID: Int, offset: Int, state: inout GameState) throws {
        let index = try editableRouteIndex(routeID, state: state)
        guard let position = state.routes[index].stops.firstIndex(where: { $0.id == stopID }) else {
            throw CommandError.unknownReference
        }
        let target = position + (offset < 0 ? -1 : 1)
        guard state.routes[index].stops.indices.contains(target) else { return }
        state.routes[index].stops.swapAt(position, target)
    }

    /// Consecutive stops in the same city form one player-visible visit. The
    /// first stop id is its stable editing id; tasks remain flat so the existing
    /// route runner can execute them without a second hierarchy.
    func routeVisitBlocks(_ stops: [RouteStop]) -> [[RouteStop]] {
        stops.reduce(into: []) { blocks, stop in
            if let last = blocks.indices.last, blocks[last].last?.cityID == stop.cityID {
                blocks[last].append(stop)
            } else {
                blocks.append([stop])
            }
        }
    }

    func addContractTaskToRoute(
        routeID: RouteID,
        visitStopID: Int,
        contractID: ContractID,
        action: ContractRouteAction,
        state: inout GameState
    ) throws {
        let routeIndex = try insertableRouteIndex(routeID, state: state)
        guard let contract = state.activeContract(contractID) else {
            throw CommandError.unknownReference
        }
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        guard let block = blocks.first(where: { $0.first?.id == visitStopID }),
              let cityID = block.first?.cityID,
              let lastStopID = block.last?.id,
              let insertionIndex = state.routes[routeIndex].stops.firstIndex(where: { $0.id == lastStopID }) else {
            throw CommandError.unknownReference
        }

        let task: RouteTask
        switch action {
        case .pickup:
            guard cityID == contract.origin else { throw CommandError.unknownReference }
            task = .pickupContract(contractID)
        case .deliver:
            // Multi-drop contracts deliver to several cities; any of them is
            // a valid delivery point for this task.
            guard contract.destinations.contains(where: { $0.cityID == cityID }) else {
                throw CommandError.unknownReference
            }
            task = .deliverContract(contractID)
        }

        // Repeated taps are harmless and must not create multiple recurring
        // claims for the same contract action on one route.
        guard !state.routes[routeIndex].stops.contains(where: {
            $0.task == task && $0.cityID == cityID
        }) else { return }
        let stop = RouteStop(id: state.issueID(), cityID: cityID, task: task)
        insertRouteStop(stop, at: insertionIndex + 1, routeIndex: routeIndex, state: &state)
    }

    /// Adds a warehouse or bulk-delivery action to a city visit. These are the
    /// tasks that turn a point-to-point lane into an actual network.
    func addNetworkTaskToRoute(
        routeID: RouteID,
        visitStopID: Int,
        task: RouteTask,
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        guard let block = blocks.first(where: { $0.first?.id == visitStopID }),
              let cityID = block.first?.cityID,
              let lastStopID = block.last?.id,
              let insertionIndex = state.routes[routeIndex].stops.firstIndex(where: { $0.id == lastStopID })
        else { throw CommandError.unknownReference }

        switch task {
        case .dropToWarehouse, .loadFromWarehouse:
            // A warehouse task without a warehouse would silently do nothing,
            // which is worse than refusing it up front.
            guard state.warehouseSite(in: cityID) != nil else { throw CommandError.warehouseRequired }
        case .deliverAll:
            break
        case .pickupLane(let laneID):
            // The dock claim only works in the lane's own origin city.
            guard catalog.lane(laneID)?.originCityID == cityID else {
                throw CommandError.unknownReference
            }
        case .deliverLane(let laneID, let target):
            switch target {
            case .destination:
                // A firm hand-over is only valid at the lane's receiver city.
                guard catalog.lane(laneID)?.destinationCityID == cityID else {
                    throw CommandError.unknownReference
                }
            case .warehouse:
                guard state.warehouseSite(in: cityID) != nil else { throw CommandError.warehouseRequired }
            }
        case .travel, .pickupShipment, .deliverShipment, .pickupContract, .deliverContract:
            throw CommandError.unknownReference
        }

        guard !state.routes[routeIndex].stops.contains(where: {
            $0.task == task && $0.cityID == cityID
        }) else { return }
        state.routes[routeIndex].stops.insert(
            RouteStop(id: state.issueID(), cityID: cityID, task: task),
            at: insertionIndex + 1
        )

        // A lane pickup with no delivery point strands its cargo (and blocks a
        // route's wind-down). Adding the pickup therefore also guarantees a
        // product-specific `deliverLane` at the lane's receiver firm — placed at
        // the front of that city's visit so the truck unloads before it reloads.
        // The player can still add warehouse drops or move it; this is only the
        // safe default that keeps the claimed cargo routable.
        //
        // Unless the route already says where the cargo goes. Sweeping a dock
        // into the city's own warehouse is a real strategy — it banks freight
        // for one big run later — and forcing
        // a delivery stop halfway across the map onto that route made it look
        // broken the moment it was built.
        let hasHandover = state.routes[routeIndex].stops.contains { stop in
            switch stop.task {
            case .dropToWarehouse: stop.cityID == cityID
            case .deliverLane(_, .warehouse): stop.cityID == cityID
            default: false
            }
        }
        if case .pickupLane(let laneID) = task,
           !hasHandover,
           let destinationCityID = catalog.lane(laneID)?.destinationCityID,
           !state.routes[routeIndex].stops.contains(where: {
               $0.cityID == destinationCityID && $0.task == .deliverLane(laneID, .destination)
           }) {
            let deliver = RouteStop(
                id: state.issueID(),
                cityID: destinationCityID,
                task: .deliverLane(laneID, .destination)
            )
            let target = state.routes[routeIndex].stops
                .firstIndex(where: { $0.cityID == destinationCityID })
                ?? state.routes[routeIndex].stops.count
            insertRouteStop(deliver, at: target, routeIndex: routeIndex, state: &state)
        }
    }

    func reorderRouteVisits(
        routeID: RouteID,
        orderedVisitIDs: [Int],
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        let currentIDs = blocks.compactMap { $0.first?.id }
        guard orderedVisitIDs.count == currentIDs.count,
              Set(orderedVisitIDs).count == orderedVisitIDs.count,
              Set(orderedVisitIDs) == Set(currentIDs) else {
            throw CommandError.unknownReference
        }
        let blocksByID = Dictionary(uniqueKeysWithValues: blocks.compactMap { block in
            block.first.map { ($0.id, block) }
        })
        state.routes[routeIndex].stops = orderedVisitIDs.flatMap { blocksByID[$0] ?? [] }
    }

    func removeRouteVisit(
        routeID: RouteID,
        visitStopID: Int,
        state: inout GameState
    ) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        let blocks = routeVisitBlocks(state.routes[routeIndex].stops)
        guard let block = blocks.first(where: { $0.first?.id == visitStopID }) else {
            throw CommandError.unknownReference
        }

        let blockStopIDs = Set(block.map(\.id))
        let removedLanePickups = Set(block.compactMap { stop -> LaneID? in
            if case .pickupLane(let id) = stop.task { return id }
            return nil
        })
        let boundJobIDs = Set(block.compactMap { stop -> JobID? in
            switch stop.task {
            case .pickupShipment(let jobID), .deliverShipment(let jobID): return jobID
            case .travel, .pickupContract, .pickupLane, .deliverContract,
                 .dropToWarehouse, .loadFromWarehouse, .deliverAll, .deliverLane: return nil
            }
        })
        let detached = try boundJobIDs.map { jobID -> Shipment in
            guard let shipment = state.shipments.first(where: {
                $0.id == jobID && $0.assignedRouteID == routeID
            }) else {
                throw CommandError.unknownReference
            }
            guard shipment.loadedVehicleID == nil else { throw CommandError.vehicleBusy }
            return shipment
        }.sorted { $0.id.rawValue < $1.id.rawValue }

        state.shipments.removeAll {
            $0.assignedRouteID == routeID && boundJobIDs.contains($0.id)
        }
        state.routes[routeIndex].stops.removeAll { stop in
            if blockStopIDs.contains(stop.id) { return true }
            switch stop.task {
            case .pickupShipment(let jobID), .deliverShipment(let jobID):
                return boundJobIDs.contains(jobID)
            case .travel, .pickupContract, .pickupLane, .deliverContract,
                 .dropToWarehouse, .loadFromWarehouse, .deliverAll, .deliverLane:
                return false
            }
        }
        // Same pairing rule as removeRouteStop: deleting the Las Vegas pickup
        // visit must clear Boston's "deliver that product" without removing Boston.
        purgeOrphanedLaneDeliveries(
            routeIndex: routeIndex,
            candidateLaneIDs: removedLanePickups,
            state: &state
        )
        for shipment in detached {
            detachShipment(shipment, state: &state)
        }
    }

    /// Accepts a market offer into a route: the cargo starts waiting at its
    /// origin firm address and pickup + delivery stops append to the lap.
    func addJobToRoute(offerID: JobID, routeID: RouteID, state: inout GameState) throws {
        guard let routeIndex = state.routes.firstIndex(where: { $0.id == routeID }),
              let offerIndex = state.offers.firstIndex(where: { $0.id == offerID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[routeIndex].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        let offer = state.offers[offerIndex]
        guard state.clock < offer.expiresAt else { throw CommandError.offerExpired }

        state.offers.remove(at: offerIndex)
        state.shipments.append(Shipment(
            id: offer.id,
            offer: offer,
            location: .address(offer.origin),
            assignedRouteID: routeID
        ))
        state.routes[routeIndex].stops.append(contentsOf: [
            RouteStop(id: state.issueID(), cityID: offer.origin, task: .pickupShipment(offer.id)),
            RouteStop(id: state.issueID(), cityID: offer.destination, task: .deliverShipment(offer.id))
        ])
        state.appendLog(.jobAccepted(jobID: offer.id, origin: offer.origin, destination: offer.destination))
        syncRouteRuns(state: &state)
    }

    func removeJobFromRoute(jobID: JobID, routeID: RouteID, state: inout GameState) throws {
        let routeIndex = try editableRouteIndex(routeID, state: state)
        guard let shipmentIndex = state.shipments.firstIndex(where: {
            $0.id == jobID && $0.assignedRouteID == routeID
        }) else {
            throw CommandError.unknownReference
        }
        guard state.shipments[shipmentIndex].loadedVehicleID == nil else {
            throw CommandError.vehicleBusy
        }
        // Cargo already resting in a warehouse is not lost when its route is
        // edited: it simply becomes free stock any other route can claim.
        if state.shipments[shipmentIndex].location.facilityID != nil {
            state.shipments[shipmentIndex].assignedRouteID = nil
            state.routes[routeIndex].stops.removeAll {
                $0.task == .pickupShipment(jobID) || $0.task == .deliverShipment(jobID)
            }
            return
        }
        let shipment = state.shipments.remove(at: shipmentIndex)
        state.routes[routeIndex].stops.removeAll {
            $0.task == .pickupShipment(jobID) || $0.task == .deliverShipment(jobID)
        }
        detachShipment(shipment, state: &state)
    }

    /// Contract obligations return to the market (or settle as missed);
    /// forfeited spot cargo simply disappears without payment.
    func detachShipment(_ shipment: Shipment, state: inout GameState) {
        guard shipment.offer.contractID != nil else { return }
        if state.clock < shipment.offer.expiresAt {
            state.offers.append(shipment.offer)
        } else {
            chargeMissedShipment(offer: shipment.offer, state: &state)
        }
    }

    func assignVehicleToRoute(routeID: RouteID, vehicleID: VehicleID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }),
              state.vehicle(vehicleID) != nil else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        guard state.route(of: vehicleID) == nil else { throw CommandError.vehicleAlreadyAssigned }
        state.routes[index].vehicleIDs.append(vehicleID)
        state.appendLog(.vehicleAssignedToRoute(vehicleID: vehicleID, routeID: routeID))
        syncRouteRuns(state: &state)
    }

    func unassignVehicleFromRoute(routeID: RouteID, vehicleID: VehicleID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }),
              state.routes[index].vehicleIDs.contains(vehicleID) else {
            throw CommandError.unknownReference
        }
        state.routes[index].vehicleIDs.removeAll { $0 == vehicleID }
        if let runIndex = state.routeRuns.firstIndex(where: { $0.vehicleID == vehicleID }) {
            state.routeRuns[runIndex].isWindingDown = true
        }
        state.appendLog(.vehicleUnassignedFromRoute(vehicleID: vehicleID, routeID: routeID))
        syncRouteRuns(state: &state)
    }

    func startRoute(_ routeID: RouteID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].cancellationRequestedAt == nil else {
            throw CommandError.routeIsRunning
        }
        guard !state.routes[index].isRunning else { return }
        guard !state.routes[index].stops.isEmpty else { throw CommandError.noRoute }
        guard !state.routes[index].vehicleIDs.isEmpty else {
            throw CommandError.noVehicleAssigned
        }
        let pickupContracts = Set(state.routes[index].stops.compactMap { stop -> ContractID? in
            if case .pickupContract(let contractID) = stop.task { return contractID }
            return nil
        })
        let deliveryContracts = Set(state.routes[index].stops.compactMap { stop -> ContractID? in
            if case .deliverContract(let contractID) = stop.task { return contractID }
            return nil
        })
        // Cargo picked up must have somewhere to go on this same lap: either a
        // matching delivery, a warehouse hand-off, or a catch-all delivery stop.
        let hasHandoff = state.routes[index].stops.contains { stop in
            switch stop.task {
            case .dropToWarehouse, .deliverAll, .deliverLane: return true
            default: return false
            }
        }
        let hasLanePickup = state.routes[index].stops.contains { stop in
            if case .pickupLane = stop.task { return true }
            return false
        }
        guard hasHandoff || (!hasLanePickup && pickupContracts.isSubset(of: deliveryContracts)) else {
            throw CommandError.incompleteRouteTasks
        }
        state.routes[index].isRunning = true
        state.routes[index].stats.markStarted(at: state.clock)
        for runIndex in state.routeRuns.indices where state.routeRuns[runIndex].routeID == routeID {
            state.routeRuns[runIndex].isWindingDown = false
        }
        state.appendLog(.routeStarted(routeID: routeID))
        syncRouteRuns(state: &state)
    }

    func stopRoute(_ routeID: RouteID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        guard state.routes[index].isRunning else { return }
        state.routes[index].isRunning = false
        for runIndex in state.routeRuns.indices where state.routeRuns[runIndex].routeID == routeID {
            state.routeRuns[runIndex].isWindingDown = true
        }
        state.appendLog(.routeStopped(routeID: routeID))
        syncRouteRuns(state: &state)
    }

    func deleteRoute(_ routeID: RouteID, state: inout GameState) throws {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else {
            throw CommandError.unknownReference
        }
        if state.routes[index].cancellationRequestedAt == nil {
            let wasRunning = state.routes[index].isRunning
            state.routes[index].isRunning = false
            state.routes[index].cancellationRequestedAt = state.clock
            for runIndex in state.routeRuns.indices where state.routeRuns[runIndex].routeID == routeID {
                state.routeRuns[runIndex].isWindingDown = true
            }
            if wasRunning {
                state.appendLog(.routeStopped(routeID: routeID))
            }
        }
        syncRouteRuns(state: &state)
    }

    /// A cancelled route remains available to its runners until committed
    /// cargo is delivered. Once the last run releases, waiting cargo is settled
    /// with the same bookkeeping as an ordinary stopped-route deletion.
    func finalizeCancelledRoutes(state: inout GameState) {
        let ready = state.routes
            .filter {
                $0.cancellationRequestedAt != nil && state.routeRuns(of: $0.id).isEmpty
            }
            .map(\.id)
            .sorted { $0.rawValue < $1.rawValue }
        for routeID in ready {
            purgeRoute(routeID, state: &state)
        }
    }

    func purgeRoute(_ routeID: RouteID, state: inout GameState) {
        guard let index = state.routes.firstIndex(where: { $0.id == routeID }) else { return }
        // Cargo resting in a warehouse survives its route's deletion — it is
        // physically stored somewhere, so it simply becomes free stock.
        for shipmentIndex in state.shipments.indices
        where state.shipments[shipmentIndex].assignedRouteID == routeID
            && state.shipments[shipmentIndex].location.facilityID != nil {
            state.shipments[shipmentIndex].assignedRouteID = nil
        }
        let orphans = state.shipments
            .filter { $0.assignedRouteID == routeID }
            .sorted { $0.id.rawValue < $1.id.rawValue }
        state.shipments.removeAll { $0.assignedRouteID == routeID }
        for shipment in orphans {
            detachShipment(shipment, state: &state)
        }
        state.routes.remove(at: index)
    }

}
