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
    /// How full the vehicle is, 0…1, against the binding constraint of its own
    /// capacity. Drawn as a fill inside the capsule, so a chain of trucks shows
    /// how much of the fleet is actually earning rather than just how many of
    /// them there are.
    let loadFraction: CGFloat
    /// Visual capsule fill 0…1 while loading/unloading (`nil` when traveling).
    /// Loading rises 0→1; unloading falls 1→0.
    let serviceProgress: CGFloat?
    /// Same map spot or overlapping name plates: 0 = lowest label, 1+ = stacked
    /// higher. Assigned by the scene from live camera scale (not the snapshot).
    let labelStackIndex: Int
    /// The line this vehicle is riding, and how far along it is.
    ///
    /// The scene needs both to move the sprite *along* the corridor between
    /// ticks. Interpolating straight to the next position instead is invisible
    /// at 1x, where a tick advances a few km, and cuts visibly across every
    /// bend at 6x, where it advances sixty minutes of driving.
    let corridor: MapCorridor?
    let progress: CGFloat

    /// Compared without the corridor: baked geometry never changes within a
    /// session, and `position` plus `progress` already say everything that
    /// moved. Comparing the point arrays of a large fleet every tick would
    /// cost more than the comparison saves.
    static func == (lhs: MapVehicleMarker, rhs: MapVehicleMarker) -> Bool {
        lhs.id == rhs.id
            && lhs.position == rhs.position
            && lhs.progress == rhs.progress
            && lhs.headingRadians == rhs.headingRadians
            && lhs.isMoving == rhs.isMoving
            && lhs.loadFraction == rhs.loadFraction
            && lhs.serviceProgress == rhs.serviceProgress
            && lhs.labelStackIndex == rhs.labelStackIndex
            && lhs.displayCode == rhs.displayCode
    }
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
        /// What each vehicle is carrying right now, summed over its shipments.
        let loadByVehicle: [VehicleID: LoadSize]

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

            var loadByVehicle: [VehicleID: LoadSize] = [:]
            for shipment in state.shipments {
                guard let vehicleID = shipment.loadedVehicleID else { continue }
                var carried = loadByVehicle[vehicleID] ?? LoadSize(massKg: 0, volumeM3: 0)
                carried.massKg += shipment.offer.load.massKg
                carried.volumeM3 += shipment.offer.load.volumeM3
                loadByVehicle[vehicleID] = carried
            }

            self.runByVehicle = runByVehicle
            self.routesByID = routesByID
            self.loadByVehicle = loadByVehicle
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
            let vehicleType = catalog.vehicleType(vehicle.typeID)
            let code = Format.vehicleCode(typeName: vehicleType?.name ?? "VEH", id: vehicle.id)
            // Domain owns the ratio (LoadSize.fillRatio); the view only draws it.
            let loadFraction = CGFloat(
                vehicleType.map { type in
                    (index.loadByVehicle[vehicle.id] ?? LoadSize(massKg: 0, volumeM3: 0))
                        .fillRatio(in: type.capacity)
                } ?? 0
            )
            if let run = index.runByVehicle[vehicle.id] {
                if let marker = routeRunMarker(
                    run: run,
                    vehicle: vehicle,
                    code: code,
                    state: state,
                    index: index,
                    loadFraction: loadFraction,
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
        loadFraction: CGFloat,
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
            let corridor = leg(run.legOriginCityID, stopCity)
            let progress = fraction(started: run.phaseStartedAt, ends: run.phaseEndsAt, clock: state.clock)
            return MapVehicleMarker(
                id: vehicle.id,
                displayCode: code,
                position: corridor.position(at: progress),
                headingRadians: corridor.heading(at: progress),
                isMoving: true,
                loadFraction: loadFraction,
                serviceProgress: nil,
                labelStackIndex: 0,
                corridor: corridor,
                progress: progress
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
                loadFraction: loadFraction,
                serviceProgress: isPickup ? progress : 1 - progress,
                labelStackIndex: 0,
                corridor: nil,
                progress: 0
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

        /// How many plates a pile may lift before the rest are simply dropped.
        ///
        /// Lifting was unbounded, which is fine at three vehicles and absurd at
        /// three hundred: a corridor carrying a full fleet threw a tower of
        /// plates hundreds of units into the sea. Past a few, no plate in the
        /// pile is readable anyway, so the honest answer is to stop drawing
        /// them and let the player zoom in or tap.
        static let maximumVisibleStack = 2

        /// Stack index meaning "do not draw this plate at all".
        static let suppressed = -1

        /// One plate-sized bucket of the world, used to find neighbours in
        /// constant time instead of by scanning the whole fleet.
        fileprivate struct Cell: Hashable {
            let column: Int
            let row: Int

            init(column: Int, row: Int) {
                self.column = column
                self.row = row
            }

            init(_ point: CGPoint, _ width: CGFloat, _ height: CGFloat) {
                column = Int((point.x / width).rounded(.down))
                row = Int((point.y / height).rounded(.down))
            }
        }

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

            // Bucket by plate-sized cells first. Scanning every vehicle for
            // every cluster member is quadratic, and this runs on each camera
            // frame — at a few hundred vehicles a pinch spent longer stacking
            // name plates than drawing the map. Neighbours can only be in the
            // nine cells around a plate, so that is all we look at.
            var grid: [Cell: [Int]] = [:]
            grid.reserveCapacity(positions.count)
            for index in positions.indices {
                grid[Cell(positions[index].position, maxDx, maxDy), default: []].append(index)
            }

            for start in positions.indices {
                guard !assigned.contains(start) else { continue }
                var cluster = [start]
                assigned.insert(start)

                var cursor = 0
                while cursor < cluster.count {
                    let anchor = positions[cluster[cursor]].position
                    let home = Cell(anchor, maxDx, maxDy)
                    for column in (home.column - 1)...(home.column + 1) {
                        for row in (home.row - 1)...(home.row + 1) {
                            for candidate in grid[Cell(column: column, row: row)] ?? [] {
                                guard !assigned.contains(candidate) else { continue }
                                let other = positions[candidate].position
                                let dx = abs(anchor.x - other.x)
                                let dy = abs(anchor.y - other.y)
                                // Axis-aligned plate test — corridor traffic
                                // mostly shares one axis, so a circle
                                // under-detects nesting.
                                guard dx < maxDx, dy < maxDy else { continue }
                                cluster.append(candidate)
                                assigned.insert(candidate)
                            }
                        }
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
                        result[positions[index].id] = stack <= maximumVisibleStack
                            ? stack
                            : suppressed
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
