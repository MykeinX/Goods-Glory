//
//  RouteTaskPicker.swift
//  Goods&Glory
//
//  What a vehicle does in one city: contract work, standing lanes out of
//  it, and the network actions that turn a lane into a hub.
//

import SwiftUI

struct RouteTaskPicker: View {
    @Environment(GameSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    let routeID: RouteID
    let visitID: Int
    let cityID: CityID
    let accent: Color

    @State private var commandError: CommandError?

    private struct TaskOption: Identifiable {
        let contract: ActiveContract
        let action: ContractRouteAction
        var id: String { "\(contract.id.rawValue)-\(action == .pickup ? "pickup" : "deliver")" }
    }

    /// Standing freight leaving this city, offered as route work.
    private struct LaneOption: Identifiable {
        let lane: FreightLane
        /// This lane ends at a city the route already visits, so taking it
        /// costs no extra driving — it fills a leg the vehicle drives anyway.
        let fitsLap: Bool
        let waitingKg: Int
        var id: String { lane.id.rawValue }
    }

    /// Lanes out of this city, the ones that fit the existing lap first. That
    /// ordering is the whole point: the fix for an empty return leg is almost
    /// always a lane running the other way between cities already on the route,
    /// and the builder should hand it to the player rather than make them
    /// discover it.
    private var laneOptions: [LaneOption] {
        guard let state = session.state, let route = state.route(routeID) else { return [] }
        let lapCities = Set(route.stops.map(\.cityID))
        return session.catalog.lanes(from: cityID)
            .map {
                LaneOption(
                    lane: $0,
                    fitsLap: lapCities.contains($0.destinationCityID),
                    waitingKg: state.laneAccrualKg[$0.id] ?? 0
                )
            }
            .sorted {
                if $0.fitsLap != $1.fitsLap { return $0.fitsLap }
                if $0.waitingKg != $1.waitingKg { return $0.waitingKg > $1.waitingKg }
                return $0.lane.id.rawValue < $1.lane.id.rawValue
            }
    }

    private var options: [TaskOption] {
        guard let state = session.state else { return [] }
        return state.activeContracts
            .flatMap { contract -> [TaskOption] in
                var result: [TaskOption] = []
                if contract.origin == cityID { result.append(TaskOption(contract: contract, action: .pickup)) }
                // Multi-drop lanes deliver in several cities.
                if contract.destinations.contains(where: { $0.cityID == cityID }) {
                    result.append(TaskOption(contract: contract, action: .deliver))
                }
                return result
            }
            .sorted { lhs, rhs in
                if lhs.contract.id == rhs.contract.id { return lhs.action == .pickup }
                return lhs.contract.id.rawValue < rhs.contract.id.rawValue
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recurring work in \(cityName)")
                        .font(.gg(12, .bold))
                        .foregroundStyle(Theme.textSecondary)

                    if options.isEmpty {
                        Text("No contract work here yet. Sign a contract connected to this city, or pick up standing freight below.")
                            .font(.gg(11.5, .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .surfacePanel(cornerRadius: 16)
                    } else {
                        ForEach(options) { option in
                            taskOptionRow(option)
                        }
                    }

                    laneSection
                    carriedFreightSection
                    networkSection
                }
                .padding(14)
            }
            .background(Theme.backgroundBottom.ignoresSafeArea())
            .navigationTitle("City Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.gg(12.5, .heavy))
                }
            }
            .alert(
                "Could Not Update Work",
                isPresented: Binding(
                    get: { commandError != nil },
                    set: { if !$0 { commandError = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Stop the route and wait for its vehicles before changing recurring work.")
            }
        }
    }

    // MARK: Standing freight

    @ViewBuilder private var laneSection: some View {
        let lanes = laneOptions
        if !lanes.isEmpty {
            Text("Standing freight from \(cityName)")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            ForEach(lanes) { option in
                laneOptionRow(option)
            }
        }
    }

    private func laneOptionRow(_ option: LaneOption) -> some View {
        let task = RouteTask.pickupLane(option.lane.id)
        let existing = session.state?.route(routeID)?.stops.first {
            $0.task == task && $0.cityID == cityID
        }
        let firm = session.catalog.firm(option.lane.originFirmID)?.name ?? cityName
        let product = session.catalog.product(option.lane.productID)?.name ?? "Freight"
        let destination = session.catalog.city(option.lane.destinationCityID)?.name
            ?? option.lane.destinationCityID.rawValue

        return Button {
            let command: GameCommand = existing.map {
                .removeRouteStop(routeID: routeID, stopID: $0.id)
            } ?? .addNetworkTaskToRoute(routeID: routeID, visitStopID: visitID, task: task)
            commandError = session.perform(command)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: session.catalog.product(option.lane.productID)?.symbol
                          ?? "shippingbox.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    // "Load here → City" — pickup is always at this visit's
                    // firm dock; the city named is the cargo's destination,
                    // not a second pickup city.
                    Text("Load here → \(destination)")
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(firm) · \(product) · ~\(Format.mass(kg: option.lane.baseRatePerDayKg))/day")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if option.fitsLap {
                        Text("Fills the leg to \(destination) you already drive")
                            .font(.gg(10, .heavy))
                            .foregroundStyle(Theme.mint)
                            .lineLimit(1)
                    } else if option.waitingKg > 0 {
                        Text("\(Format.mass(kg: option.waitingKg)) waiting · adds a stop")
                            .font(.gg(10, .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
                Image(systemName: existing == nil ? "plus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(existing == nil ? Theme.textTertiary : accent)
            }
            .padding(12)
            .surfacePanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: Drop what you picked up earlier

    /// Lanes already claimed at an earlier stop on this lap — the products
    /// physically aboard by the time the truck reaches this city. Everything
    /// up to and including this visit counts, so the player can even unload in
    /// the same city they loaded (a deliberate consolidation move).
    private var carriedLanes: [FreightLane] {
        guard let state = session.state, let route = state.route(routeID),
              let start = route.stops.firstIndex(where: { $0.id == visitID }) else { return [] }
        var last = start
        while last + 1 < route.stops.count, route.stops[last + 1].cityID == cityID {
            last += 1
        }
        var laneIDs: [LaneID] = []
        for stop in route.stops.prefix(last + 1) {
            if case .pickupLane(let id) = stop.task, !laneIDs.contains(id) {
                laneIDs.append(id)
            }
        }
        return laneIDs.compactMap { session.catalog.lane($0) }
    }

    /// For each carried product, the places it can go here: its receiver firm
    /// (only in the destination city) and this city's warehouse. This is the
    /// heart of the strategic route: each product routed independently.
    @ViewBuilder private var carriedFreightSection: some View {
        let lanes = carriedLanes
        let hasWarehouse = session.state?.warehouseSite(in: cityID) != nil
        let deliverHere = lanes.filter { $0.destinationCityID == cityID }
        if !deliverHere.isEmpty || (hasWarehouse && !lanes.isEmpty) {
            Text("Drop freight you picked up")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            ForEach(deliverHere) { lane in
                let firm = session.catalog.firm(lane.destinationFirmID)?.name ?? cityName
                let product = session.catalog.product(lane.productID)?.name ?? "Freight"
                networkRow(
                    task: .deliverLane(lane.id, .destination),
                    symbol: "tray.and.arrow.down.fill",
                    tint: Theme.mint,
                    title: String(localized: "Deliver \(product) → \(firm)"),
                    detail: String(localized: "Hand this product to its receiver firm and collect payment")
                )
            }
            if hasWarehouse {
                ForEach(lanes) { lane in
                    let product = session.catalog.product(lane.productID)?.name ?? "Freight"
                    networkRow(
                        task: .deliverLane(lane.id, .warehouse),
                        symbol: "shippingbox.fill",
                        tint: Theme.sky,
                        title: String(localized: "Store \(product) here"),
                        detail: String(localized: "Hold this product in \(cityName)'s warehouse for a later leg")
                    )
                }
            }
        }
    }

    // MARK: Network actions

    /// The three tasks that turn a lane into a network: store here, collect a
    /// lot from here, drop everything that belongs here.
    @ViewBuilder private var networkSection: some View {
        let warehouse = session.state?.warehouseSite(in: cityID)
        VStack(alignment: .leading, spacing: 10) {
            Text("Network actions")
                .font(.gg(12, .bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 6)

            networkRow(
                task: .deliverAll,
                symbol: "tray.and.arrow.down.fill",
                tint: Theme.mint,
                title: String(localized: "Deliver everything for this city"),
                detail: String(localized: "Unload every carried parcel whose destination is \(cityName)")
            )

            if let warehouse {
                networkRow(
                    task: .dropToWarehouse,
                    symbol: "shippingbox.fill",
                    tint: Theme.sky,
                    title: String(localized: "Store in the warehouse"),
                    detail: String(localized: "Drop everything not yet home, so another route can finish it")
                )
                lotOptions(warehouse: warehouse)
            } else {
                Text("Build a warehouse in \(cityName) to store and collect freight here.")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    @ViewBuilder private func lotOptions(warehouse: Facility) -> some View {
        if let state = session.state {
            let lots = state.storageLots(in: warehouse.id)
            if lots.isEmpty {
                Text("The warehouse is empty — nothing to collect yet.")
                    .font(.gg(11, .bold))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(lots) { lot in
                    let destination = session.catalog.city(lot.key.destinationCityID)?.name
                        ?? lot.key.destinationCityID.rawValue
                    let product = session.catalog.product(lot.key.productID)?.name
                        ?? lot.key.productID.rawValue
                    networkRow(
                        task: .loadFromWarehouse(lot.key),
                        symbol: "shippingbox.and.arrow.backward.fill",
                        tint: accent,
                        title: String(localized: "Collect \(product) → \(destination)"),
                        detail: String(localized: "\(lot.parcelCount) parcel(s) · \(Format.mass(kg: lot.load.massKg)) · \(Format.money(lot.pendingPayout)) on delivery")
                    )
                }
            }
        }
    }

    private func networkRow(
        task: RouteTask,
        symbol: String,
        tint: Color,
        title: String,
        detail: String
    ) -> some View {
        let existing = session.state?.route(routeID)?.stops.first {
            $0.cityID == cityID && $0.task == task
        }
        return Button {
            let command: GameCommand = existing.map {
                .removeRouteStop(routeID: routeID, stopID: $0.id)
            } ?? .addNetworkTaskToRoute(routeID: routeID, visitStopID: visitID, task: task)
            commandError = session.perform(command)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(detail)
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: existing == nil ? "plus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(existing == nil ? Theme.textTertiary : tint)
            }
            .padding(12)
            .surfacePanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func taskOptionRow(_ option: TaskOption) -> some View {
        let selectedStop = matchingStop(option)
        let pickup = option.action == .pickup
        let firmID = pickup ? option.contract.originFirmID : option.contract.destinationFirmID
        let firm = firmID.flatMap(session.catalog.firm)?.name ?? cityName
        let product = session.catalog.product(option.contract.productID)?.name ?? "Freight"
        let pending = session.state?.offers.count {
            $0.source == .contract && $0.contractID == option.contract.id
        } ?? 0

        return Button {
            let command: GameCommand
            if let selectedStop {
                command = .removeRouteStop(routeID: routeID, stopID: selectedStop.id)
            } else {
                command = .addContractTaskToRoute(
                    routeID: routeID,
                    visitStopID: visitID,
                    contractID: option.contract.id,
                    action: option.action
                )
            }
            commandError = session.perform(command)
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill((pickup ? accent : Theme.mint).opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: pickup ? "tray.and.arrow.up.fill" : "tray.and.arrow.down.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(pickup ? accent : Theme.mint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(pickup ? "Pick up contract freight" : "Deliver contract freight")
                        .font(.gg(13, .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(firm) · \(product) · \(Format.mass(kg: option.contract.parcelMassKg))")
                        .font(.gg(10.5, .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Text("\(pending) waiting · every \(Format.duration(minutes: option.contract.shipmentIntervalMinutes))")
                        .font(.gg(9.5, .bold))
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 4)
                Image(systemName: selectedStop == nil ? "plus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(selectedStop == nil ? accent : Theme.mint)
            }
            .padding(12)
            .surfacePanel(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func matchingStop(_ option: TaskOption) -> RouteStop? {
        session.state?.route(routeID)?.stops.first { stop in
            switch (option.action, stop.task) {
            case (.pickup, .pickupContract(let id)): return id == option.contract.id
            case (.deliver, .deliverContract(let id)): return id == option.contract.id
            default: return false
            }
        }
    }

    private var cityName: String {
        session.catalog.city(cityID)?.name ?? cityID.rawValue
    }
}

