//
//  MapSceneAdapter.swift
//  Goods&Glory
//
//  Converts deterministic domain state into a read-only SpriteKit snapshot.
//  Every active route and vehicle reads the same schematic road atlas.
//  SpriteKit never reads or mutates GameState and the simulation never sees
//  scene nodes.
//

import CoreGraphics
import Foundation

/// Shared map tap / highlight selection (design 1b).
enum MapSelection: Equatable, Hashable {
    case none
    case city(CityID)
    case vehicle(VehicleID)

    var cityID: CityID? {
        if case .city(let id) = self { return id }
        return nil
    }

    var vehicleID: VehicleID? {
        if case .vehicle(let id) = self { return id }
        return nil
    }
}

/// Initial / locked camera framing for a map surface.
enum MapCameraFocus: Equatable {
    /// Strategic overview — HQ-centered opening frame (first map open only).
    case world
    /// Keep the current camera; do not reframe.
    case free
    /// City centered at the closest allowed zoom (detail headers).
    case city(CityID)
    /// Fit the listed cities in view. Insets reserve space for chrome that
    /// overlays the *same* map surface (status strip, bottom card, tab bar).
    /// Do not invent insets for UI that lives *below* the map in the layout
    /// (e.g. the route builder editor panel) — that just zooms out for empty space.
    case route(cities: [CityID], topInset: CGFloat, bottomInset: CGFloat)

    /// Full-screen live map defaults: status chrome above, city card / tab bar below.
    static func route(_ cities: [CityID]) -> MapCameraFocus {
        .route(cities: cities, topInset: 130, bottomInset: 126)
    }

    /// Frames a whole continent. Built from its cities rather than a hardcoded
    /// bounding box, so adding a city to a continent reframes it automatically.
    static func continent(_ continent: Continent, catalog: GameCatalog, bottomInset: CGFloat) -> MapCameraFocus {
        let cities = catalog.cities.filter { $0.continent == continent }.map(\.id)
        guard !cities.isEmpty else { return .world }
        return .route(cities: cities, topInset: 80, bottomInset: bottomInset)
    }
}

/// One-shot request to pan the live map to a city without changing zoom.
/// A fresh `id` lets the same city be requested again (e.g. two taps).
struct MapCameraPanRequest: Equatable, Identifiable {
    let id: UUID
    let cityID: CityID
    /// Screen points hidden by chrome sitting over the bottom of the map (the
    /// city sheet). The city is centered in what is left visible above it.
    let bottomInset: CGFloat

    init(cityID: CityID, bottomInset: CGFloat = 0) {
        self.id = UUID()
        self.cityID = cityID
        self.bottomInset = bottomInset
    }
}

struct MapVehicleMarker: Identifiable, Equatable {
    let id: VehicleID
    let displayCode: String
    let position: CGPoint
    let headingRadians: CGFloat
    let isMoving: Bool
    /// Cargo state belongs on the vehicle, not on a duplicate route stroke.
    let isLoaded: Bool
    /// Visual capsule fill 0…1 while loading/unloading (`nil` when traveling).
    /// Loading rises 0→1; unloading falls 1→0.
    let serviceProgress: CGFloat?
    /// Same map spot or overlapping name plates: 0 = lowest label, 1+ = stacked
    /// higher. Assigned by the scene from live camera scale (not the snapshot).
    let labelStackIndex: Int
}

enum MapRouteKind: Hashable {
    /// Union of the canonical roads used by all currently running routes.
    case active
    /// Player-authored route preview, independent from live vehicle movement.
    case planned
}

struct MapRouteOverlay: Identifiable, Equatable {
    let id: String
    /// One shared road section (or the continuous planned lap), already
    /// projected by the schematic atlas.
    let anchors: [CGPoint]
    let kind: MapRouteKind
}

/// A compact route-plan marker grouped by physical city. A city visited more
/// than once renders one marker such as `1·4`, matching the route builder.
struct MapPlannedVisitMarker: Identifiable, Equatable {
    let id: CityID
    let position: CGPoint
    let stepNumbers: [Int]
    let hasPickup: Bool
    let hasDelivery: Bool
}

/// What the player owns in a city, drawn as a small icon strip under the pin.
struct MapCityFacilities: Equatable {
    let hasOffice: Bool
    let hasWarehouse: Bool
    /// True while anything there is still under construction.
    let isBuilding: Bool
}

/// Freight in a city that needs the player's attention, surfaced as a single
/// badge so the map stays readable. Only the count and urgency are shown; the
/// detail lives in the city screen.
struct MapCityAttention: Equatable {
    /// Parcels stored in this city's warehouse awaiting an onward leg.
    let storedParcels: Int
    /// Fraction of the tightest delivery window already spent, 0...1.
    /// Drives the badge colour: calm, then warning, then late.
    let urgency: Double

    var total: Int { storedParcels }
}

struct MapRenderSnapshot: Equatable {
    let vehicles: [MapVehicleMarker]
    let routes: [MapRouteOverlay]
    let plannedVisits: [MapPlannedVisitMarker]
    /// Idle vehicles parked at a city — shown as a count badge on the city, not as sprites.
    let idleFleetByCity: [CityID: Int]
    let facilitiesByCity: [CityID: MapCityFacilities]
    let attentionByCity: [CityID: MapCityAttention]

    static let empty = MapRenderSnapshot(
        vehicles: [],
        routes: [],
        plannedVisits: [],
        idleFleetByCity: [:],
        facilitiesByCity: [:],
        attentionByCity: [:]
    )
}


enum MapSceneAdapter {
    /// Per-snapshot lookup tables. Built once in O(n) and read in O(1), instead
    /// of rescanning the same arrays for every vehicle.
    private struct Index {
        let runByVehicle: [VehicleID: RouteRun]
        let routesByID: [RouteID: Route]
        /// Vehicles currently carrying at least one shipment.
        let loadedVehicleIDs: Set<VehicleID>

        init(state: GameState) {
            // First-wins, matching the `first { }` lookups these replace. A
            // vehicle should never have two runs, but the index must not quietly
            // change behaviour if the invariant is ever broken.
            var runByVehicle: [VehicleID: RouteRun] = [:]
            runByVehicle.reserveCapacity(state.routeRuns.count)
            for run in state.routeRuns where runByVehicle[run.vehicleID] == nil {
                runByVehicle[run.vehicleID] = run
            }

            var routesByID: [RouteID: Route] = [:]
            routesByID.reserveCapacity(state.routes.count)
            for route in state.routes where routesByID[route.id] == nil {
                routesByID[route.id] = route
            }

            var loaded: Set<VehicleID> = []
            for shipment in state.shipments {
                if let vehicleID = shipment.loadedVehicleID { loaded.insert(vehicleID) }
            }

            self.runByVehicle = runByVehicle
            self.routesByID = routesByID
            self.loadedVehicleIDs = loaded
        }
    }

    @MainActor
    static func snapshot(
        state: GameState,
        catalog: GameCatalog,
        projection: MapProjection,
        previewRoute: Route? = nil,
        corridors providedCorridors: MapCorridorCache? = nil
    ) -> MapRenderSnapshot {
        let corridors = providedCorridors ?? .shared
        var markers: [MapVehicleMarker] = []
        var routes: [MapRouteOverlay] = []
        var idleCountPerCity: [CityID: Int] = [:]

        // This runs once per simulation tick for the whole fleet. Looking each
        // vehicle's run / route up with `first { }` made the snapshot cost grow
        // with the fleet; indexing once keeps it linear.
        let index = Index(state: state)
        routes = activeNetworkOverlays(
            state: state,
            catalog: catalog,
            projection: projection,
            corridors: corridors
        )

        // City projections are pure trigonometry on immutable catalog data and
        // the same handful of cities recur across every vehicle and leg.
        var pointCache: [CityID: CGPoint] = [:]
        func point(_ id: CityID) -> CGPoint {
            if let cached = pointCache[id] { return cached }
            let value = catalog.city(id).map(projection.point(for:)) ?? .zero
            pointCache[id] = value
            return value
        }

        // Every drawn leg and every vehicle position comes from here, so the
        // line on screen and the truck riding it can never diverge.
        func leg(_ from: CityID, _ to: CityID) -> MapCorridor {
            corridors.corridor(from: from, to: to, catalog: catalog, projection: projection)
        }

        // Sorted by ID for stable iteration order.
        for vehicle in state.vehicles.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let typeName = catalog.vehicleType(vehicle.typeID)?.name ?? "VEH"
            let code = Format.vehicleCode(typeName: typeName, id: vehicle.id)
            if let run = index.runByVehicle[vehicle.id] {
                if let marker = routeRunMarker(
                    run: run,
                    vehicle: vehicle,
                    code: code,
                    state: state,
                    index: index,
                    point: point,
                    leg: leg
                ) {
                    markers.append(marker)
                } else {
                    idleCountPerCity[vehicle.cityID, default: 0] += 1
                }
                continue
            }
            // Idle fleet is summarized on the city label — no per-vehicle sprite.
            idleCountPerCity[vehicle.cityID, default: 0] += 1
        }

        let plannedVisits: [MapPlannedVisitMarker]
        if let previewRoute {
            let preview = routePreview(
                route: previewRoute,
                catalog: catalog,
                projection: projection,
                corridors: corridors
            )
            routes.append(contentsOf: preview.overlays)
            plannedVisits = preview.markers
        } else {
            plannedVisits = []
        }

        return MapRenderSnapshot(
            vehicles: markers,
            routes: routes,
            plannedVisits: plannedVisits,
            idleFleetByCity: idleCountPerCity,
            facilitiesByCity: facilities(in: state),
            attentionByCity: attention(in: state)
        )
    }

    private static func facilities(in state: GameState) -> [CityID: MapCityFacilities] {
        var result: [CityID: MapCityFacilities] = [:]
        for facility in state.facilities {
            let existing = result[facility.cityID]
            let building = facility.modules.contains {
                !$0.isOperational(at: state.clock) || $0.isUpgrading
            }
            result[facility.cityID] = MapCityFacilities(
                hasOffice: (existing?.hasOffice ?? false) || facility.module(.office) != nil,
                hasWarehouse: (existing?.hasWarehouse ?? false) || facility.module(.warehouse) != nil,
                isBuilding: (existing?.isBuilding ?? false) || building
            )
        }
        return result
    }

    /// Cargo the player still has to act on, per city. Anything already on a
    /// truck is handled and would just be noise on the map.
    private static func attention(in state: GameState) -> [CityID: MapCityAttention] {
        var stored: [CityID: Int] = [:]
        // Smallest remaining fraction of the delivery window, per city.
        var tightest: [CityID: Double] = [:]

        func noteUrgency(city: CityID, createdAt: GameTime, expiresAt: GameTime) {
            let window = max(1, createdAt.minutes(until: expiresAt))
            let spent = Double(createdAt.minutes(until: state.clock)) / Double(window)
            tightest[city] = max(tightest[city] ?? 0, min(1, max(0, spent)))
        }

        // Indexed rather than `state.facility(id)` per shipment, which would be
        // O(shipments × facilities) on every tick.
        var cityByFacility: [FacilityID: CityID] = [:]
        cityByFacility.reserveCapacity(state.facilities.count)
        for facility in state.facilities { cityByFacility[facility.id] = facility.cityID }

        for shipment in state.shipments {
            guard let facilityID = shipment.location.facilityID,
                  let cityID = cityByFacility[facilityID] else { continue }
            stored[cityID, default: 0] += 1
            noteUrgency(
                city: cityID,
                createdAt: shipment.offer.createdAt,
                expiresAt: shipment.offer.expiresAt
            )
        }

        var result: [CityID: MapCityAttention] = [:]
        for cityID in stored.keys {
            result[cityID] = MapCityAttention(
                storedParcels: stored[cityID] ?? 0,
                urgency: tightest[cityID] ?? 0
            )
        }
        return result
    }

    /// Marker for a vehicle executing a route. Returns nil when it is parked
    /// (waiting), so it folds into the idle city summary.
    private static func routeRunMarker(
        run: RouteRun,
        vehicle: Vehicle,
        code: String,
        state: GameState,
        index: Index,
        point: (CityID) -> CGPoint,
        leg: (CityID, CityID) -> MapCorridor
    ) -> MapVehicleMarker? {
        guard let route = index.routesByID[run.routeID],
              route.stops.indices.contains(run.stopIndex) else { return nil }
        let stopCity = route.stops[run.stopIndex].cityID
        let stopPt = point(stopCity)

        switch run.phase {
        case .waiting:
            return nil

        case .traveling:
            let originPt = point(run.legOriginCityID)
            guard originPt != stopPt else { return nil }
            let loaded = index.loadedVehicleIDs.contains(vehicle.id)
            let corridor = leg(run.legOriginCityID, stopCity)
            let progress = fraction(started: run.phaseStartedAt, ends: run.phaseEndsAt, clock: state.clock)
            return MapVehicleMarker(
                id: vehicle.id,
                displayCode: code,
                position: corridor.position(at: progress),
                headingRadians: corridor.heading(at: progress),
                isMoving: true,
                isLoaded: loaded,
                serviceProgress: nil,
                labelStackIndex: 0
            )

        case .servicing:
            let progress = fraction(started: run.phaseStartedAt, ends: run.phaseEndsAt, clock: state.clock)
            let isPickup: Bool
            switch route.stops[run.stopIndex].task {
            case .pickupLane, .loadFromWarehouse: isPickup = true
            default: isPickup = false
            }
            return MapVehicleMarker(
                id: vehicle.id,
                displayCode: code,
                position: stopPt,
                headingRadians: 0,
                isMoving: false,
                isLoaded: index.loadedVehicleIDs.contains(vehicle.id),
                serviceProgress: isPickup ? progress : 1 - progress,
                labelStackIndex: 0
            )
        }
    }

    /// Stacks vehicle name plates when their on-screen capsules start to nest.
    /// Labels are counter-scaled with the camera, so the threshold is expressed
    /// in world units via `nodeScale` (= camera × semantic scale).
    enum VehicleLabelStacking {
        /// Typical name-plate size in vehicle-node local units.
        static let plateLocalWidth: CGFloat = 40
        static let plateLocalHeight: CGFloat = 12
        /// Start stacking once plates are this far into each other (0.18 ≈ 18%).
        static let overlapStart: CGFloat = 0.18

        static func indices(
            positions: [(id: VehicleID, position: CGPoint)],
            nodeScale: CGFloat
        ) -> [VehicleID: Int] {
            guard positions.count > 1, nodeScale > 0 else {
                return Dictionary(uniqueKeysWithValues: positions.map { ($0.id, 0) })
            }

            let maxDx = plateLocalWidth * nodeScale * (1 - overlapStart)
            let maxDy = plateLocalHeight * nodeScale * (1 - overlapStart)
            guard maxDx > 0, maxDy > 0 else {
                return Dictionary(uniqueKeysWithValues: positions.map { ($0.id, 0) })
            }

            var result: [VehicleID: Int] = [:]
            result.reserveCapacity(positions.count)
            var assigned = Set<Int>()
            assigned.reserveCapacity(positions.count)

            for start in positions.indices {
                guard !assigned.contains(start) else { continue }
                var cluster = [start]
                assigned.insert(start)

                var cursor = 0
                while cursor < cluster.count {
                    let anchor = positions[cluster[cursor]].position
                    for candidate in positions.indices where !assigned.contains(candidate) {
                        let other = positions[candidate].position
                        let dx = abs(anchor.x - other.x)
                        let dy = abs(anchor.y - other.y)
                        // Axis-aligned plate test — corridor traffic mostly
                        // shares one axis, so a circle under-detects nesting.
                        guard dx < maxDx, dy < maxDy else { continue }
                        cluster.append(candidate)
                        assigned.insert(candidate)
                    }
                    cursor += 1
                }

                let ordered = cluster.sorted {
                    positions[$0].id.rawValue < positions[$1].id.rawValue
                }
                if ordered.count == 1 {
                    result[positions[ordered[0]].id] = 0
                } else {
                    for (stack, index) in ordered.enumerated() {
                        result[positions[index].id] = stack
                    }
                }
            }
            return result
        }
    }

    private static func fraction(started: GameTime, ends: GameTime, clock: GameTime) -> CGFloat {
        let total = max(1, started.minutes(until: ends))
        let elapsed = started.minutes(until: clock)
        return CGFloat(min(1, max(0, Double(elapsed) / Double(total))))
    }

}
