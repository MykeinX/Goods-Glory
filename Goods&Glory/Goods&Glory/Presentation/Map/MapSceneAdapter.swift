//
//  MapSceneAdapter.swift
//  Goods&Glory
//
//  Converts deterministic domain state into a read-only SpriteKit snapshot.
//  Following the design language, routes are drawn as smooth city-to-city arcs
//  (not road-following polylines), and vehicles ride those same arcs. SpriteKit
//  never reads or mutates GameState and the simulation never sees scene nodes.
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
    /// Fit the listed cities in view. `bottomInset` reserves space for bottom UI
    /// (route editor panel, map city card, tab bar).
    case route(cities: [CityID], bottomInset: CGFloat)

    /// Default inset used by the route builder map strip.
    static func route(_ cities: [CityID]) -> MapCameraFocus {
        .route(cities: cities, bottomInset: 126)
    }
}

/// One-shot request to pan the live map to a city without changing zoom.
/// A fresh `id` lets the same city be requested again (e.g. two taps).
struct MapCameraPanRequest: Equatable, Identifiable {
    let id: UUID
    let cityID: CityID

    init(cityID: CityID) {
        self.id = UUID()
        self.cityID = cityID
    }
}

struct MapVehicleMarker: Identifiable, Equatable {
    let id: VehicleID
    let displayCode: String
    let position: CGPoint
    let headingRadians: CGFloat
    let isMoving: Bool
    /// Visual capsule fill 0…1 while loading/unloading (`nil` when traveling).
    /// Loading rises 0→1; unloading falls 1→0.
    let serviceProgress: CGFloat?
    /// Stationed at a city: 0 = just above the city name, 1+ = stacked higher.
    let labelStackIndex: Int
}

enum MapRouteKind: Hashable {
    case loaded
    case deadhead
    /// Player-authored route preview, independent from live vehicle movement.
    case planned
    /// Ephemeral spot-job preview on the live map (thin dashed arc).
    case preview
}

struct MapRouteOverlay: Identifiable, Equatable {
    let id: String
    /// Ordered city anchor points; consecutive pairs are joined by a quad arc.
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
    let hasBranch: Bool
    let hasWarehouse: Bool
    /// True while anything there is still under construction.
    let isBuilding: Bool
}

/// Freight in a city that needs the player's attention, surfaced as a single
/// badge so the map stays readable. Only the count and urgency are shown; the
/// detail lives in the city screen.
struct MapCityAttention: Equatable {
    /// Contract parcels posted from this city and not yet claimed.
    let waitingParcels: Int
    /// Parcels stored in this city's warehouse awaiting an onward leg.
    let storedParcels: Int
    /// Fraction of the tightest delivery window already spent, 0...1.
    /// Drives the badge colour: calm, then warning, then late.
    let urgency: Double

    var total: Int { waitingParcels + storedParcels }
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

/// Shared quadratic-arc geometry so the scene draws exactly the curve the
/// vehicles travel along. Mirrors the design's `leg()` control-point math.
enum MapArc {
    private static let bow: CGFloat = 0.14

    static func control(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(
            x: (a.x + b.x) / 2 + (a.y - b.y) * bow,
            y: (a.y + b.y) / 2 + (b.x - a.x) * bow
        )
    }

    static func point(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let c = control(a, b)
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * a.x + 2 * mt * t * c.x + t * t * b.x,
            y: mt * mt * a.y + 2 * mt * t * c.y + t * t * b.y
        )
    }

    static func heading(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGFloat {
        let c = control(a, b)
        let dx = 2 * (1 - t) * (c.x - a.x) + 2 * t * (b.x - c.x)
        let dy = 2 * (1 - t) * (c.y - a.y) + 2 * t * (b.y - c.y)
        return atan2(dy, dx)
    }
}

enum MapSceneAdapter {
    static func snapshot(
        state: GameState,
        catalog: GameCatalog,
        projection: MapProjection,
        previewRoute: Route? = nil
    ) -> MapRenderSnapshot {
        var markers: [MapVehicleMarker] = []
        var routes: [MapRouteOverlay] = []
        var idleCountPerCity: [CityID: Int] = [:]
        var labelStackByCity: [CityID: Int] = [:]

        func point(_ id: CityID) -> CGPoint {
            catalog.city(id).map(projection.point(for:)) ?? .zero
        }

        // Sorted by ID for stable iteration order.
        for vehicle in state.vehicles.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            let typeName = catalog.vehicleType(vehicle.typeID)?.name ?? "VEH"
            let code = Format.vehicleCode(typeName: typeName, id: vehicle.id)
            if let run = state.routeRun(for: vehicle.id) {
                if let marker = routeRunMarker(
                    run: run,
                    vehicle: vehicle,
                    code: code,
                    state: state,
                    point: point,
                    overlays: &routes
                ) {
                    markers.append(marker)
                } else {
                    idleCountPerCity[vehicle.cityID, default: 0] += 1
                }
                continue
            }
            guard let job = state.activeJob(for: vehicle.id) else {
                // Idle fleet is summarized on the city label — no per-vehicle sprite.
                idleCountPerCity[vehicle.cityID, default: 0] += 1
                continue
            }

            let originPt = point(job.offer.origin)
            let destPt = point(job.offer.destination)
            let vehiclePt = point(vehicle.cityID)

            // Deadhead arc (dashed): from the vehicle's city to the pickup.
            if job.phase == .deadheading, vehiclePt != originPt {
                routes.append(MapRouteOverlay(
                    id: "\(job.id.rawValue)-deadhead",
                    anchors: [vehiclePt, originPt],
                    kind: .deadhead
                ))
            }
            // Loaded arc (solid, brand): pickup to delivery.
            routes.append(MapRouteOverlay(
                id: "\(job.id.rawValue)-loaded",
                anchors: [originPt, destPt],
                kind: .loaded
            ))

            let progress = fraction(of: job, clock: state.clock)
            let placement = placement(
                for: job,
                originPt: originPt,
                destPt: destPt,
                vehiclePt: vehiclePt,
                progress: progress
            )
            let isServicing = job.phase == .loading || job.phase == .unloading
            var labelStackIndex = 0
            if isServicing {
                let cityID = job.phase == .loading ? job.offer.origin : job.offer.destination
                labelStackIndex = labelStackByCity[cityID, default: 0]
                labelStackByCity[cityID] = labelStackIndex + 1
            }
            // Loading: 0→1 fill. Unloading: 1→0 drain.
            let serviceProgress: CGFloat? = {
                guard isServicing else { return nil }
                return job.phase == .unloading ? 1 - progress : progress
            }()
            markers.append(MapVehicleMarker(
                id: vehicle.id,
                displayCode: code,
                position: placement.position,
                headingRadians: placement.heading,
                isMoving: job.phase == .deadheading || job.phase == .enRoute,
                serviceProgress: serviceProgress,
                labelStackIndex: labelStackIndex
            ))
        }

        let plannedVisits: [MapPlannedVisitMarker]
        if let previewRoute {
            let preview = routePreview(
                route: previewRoute,
                catalog: catalog,
                projection: projection
            )
            if let overlay = preview.overlay {
                routes.append(overlay)
            }
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
            let building = !facility.isOperational(at: state.clock) || facility.isUpgrading
            result[facility.cityID] = MapCityFacilities(
                hasBranch: (existing?.hasBranch ?? false) || facility.kind == .branch,
                hasWarehouse: (existing?.hasWarehouse ?? false) || facility.kind == .warehouse,
                isBuilding: (existing?.isBuilding ?? false) || building
            )
        }
        return result
    }

    /// Cargo the player still has to act on, per city. Deliberately narrow:
    /// only unclaimed contract parcels and warehouse stock. Anything already
    /// on a truck is handled and would just be noise on the map.
    private static func attention(in state: GameState) -> [CityID: MapCityAttention] {
        var waiting: [CityID: Int] = [:]
        var stored: [CityID: Int] = [:]
        // Smallest remaining fraction of the delivery window, per city.
        var tightest: [CityID: Double] = [:]

        func noteUrgency(city: CityID, createdAt: GameTime, expiresAt: GameTime) {
            let window = max(1, createdAt.minutes(until: expiresAt))
            let spent = Double(createdAt.minutes(until: state.clock)) / Double(window)
            tightest[city] = max(tightest[city] ?? 0, min(1, max(0, spent)))
        }

        for offer in state.offers where offer.source == .contract {
            waiting[offer.origin, default: 0] += 1
            noteUrgency(city: offer.origin, createdAt: offer.createdAt, expiresAt: offer.expiresAt)
        }
        for shipment in state.shipments {
            guard let facilityID = shipment.location.facilityID,
                  let facility = state.facility(facilityID) else { continue }
            stored[facility.cityID, default: 0] += 1
            noteUrgency(
                city: facility.cityID,
                createdAt: shipment.offer.createdAt,
                expiresAt: shipment.offer.expiresAt
            )
        }

        var result: [CityID: MapCityAttention] = [:]
        for cityID in Set(waiting.keys).union(stored.keys) {
            result[cityID] = MapCityAttention(
                waitingParcels: waiting[cityID] ?? 0,
                storedParcels: stored[cityID] ?? 0,
                urgency: tightest[cityID] ?? 0
            )
        }
        return result
    }

    /// Consecutive task stops in the same city form one visit. The route path
    /// closes back to its first visit, while markers group non-consecutive
    /// visits to the same physical city (`A → B → A` becomes `1·3` at A).
    private static func routePreview(
        route: Route,
        catalog: GameCatalog,
        projection: MapProjection
    ) -> (overlay: MapRouteOverlay?, markers: [MapPlannedVisitMarker]) {
        struct Visit {
            let cityID: CityID
            var hasPickup: Bool
            var hasDelivery: Bool
        }

        var visits: [Visit] = []
        for stop in route.stops {
            let flags: (pickup: Bool, delivery: Bool)
            switch stop.task {
            case .pickupShipment, .pickupContract, .loadFromWarehouse:
                flags = (true, false)
            case .deliverShipment, .deliverContract, .deliverAll, .dropToWarehouse:
                flags = (false, true)
            case .travel:
                flags = (false, false)
            }

            if let lastIndex = visits.indices.last,
               visits[lastIndex].cityID == stop.cityID {
                visits[lastIndex].hasPickup = visits[lastIndex].hasPickup || flags.pickup
                visits[lastIndex].hasDelivery = visits[lastIndex].hasDelivery || flags.delivery
            } else {
                visits.append(Visit(
                    cityID: stop.cityID,
                    hasPickup: flags.pickup,
                    hasDelivery: flags.delivery
                ))
            }
        }

        var markerOrder: [CityID] = []
        var markerValues: [CityID: (steps: [Int], pickup: Bool, delivery: Bool)] = [:]
        for (index, visit) in visits.enumerated() {
            var value = markerValues[visit.cityID]
                ?? (steps: [], pickup: false, delivery: false)
            if markerValues[visit.cityID] == nil {
                markerOrder.append(visit.cityID)
            }
            value.steps.append(index + 1)
            value.pickup = value.pickup || visit.hasPickup
            value.delivery = value.delivery || visit.hasDelivery
            markerValues[visit.cityID] = value
        }

        let plannedMarkers = markerOrder.compactMap { cityID -> MapPlannedVisitMarker? in
            guard let city = catalog.city(cityID), let value = markerValues[cityID] else { return nil }
            return MapPlannedVisitMarker(
                id: cityID,
                position: projection.point(for: city),
                stepNumbers: value.steps,
                hasPickup: value.pickup,
                hasDelivery: value.delivery
            )
        }

        var anchorCityIDs = visits.map(\.cityID)
        if anchorCityIDs.count > 1,
           let first = anchorCityIDs.first,
           anchorCityIDs.last != first {
            anchorCityIDs.append(first)
        }
        let anchors = anchorCityIDs.compactMap { cityID in
            catalog.city(cityID).map(projection.point(for:))
        }
        let overlay: MapRouteOverlay? = anchors.count > 1
            ? MapRouteOverlay(
                id: "preview-\(route.id.rawValue)",
                anchors: anchors,
                kind: .planned
            )
            : nil
        return (overlay, plannedMarkers)
    }

    /// Marker + overlay for a vehicle executing a route. Returns nil when the
    /// vehicle is parked (waiting), so it folds into the idle city summary.
    private static func routeRunMarker(
        run: RouteRun,
        vehicle: Vehicle,
        code: String,
        state: GameState,
        point: (CityID) -> CGPoint,
        overlays: inout [MapRouteOverlay]
    ) -> MapVehicleMarker? {
        guard let route = state.route(run.routeID),
              route.stops.indices.contains(run.stopIndex) else { return nil }
        let stopCity = route.stops[run.stopIndex].cityID
        let stopPt = point(stopCity)

        switch run.phase {
        case .waiting:
            return nil

        case .traveling:
            let originPt = point(run.legOriginCityID)
            guard originPt != stopPt else { return nil }
            let loaded = state.shipments.contains { $0.loadedVehicleID == vehicle.id }
            overlays.append(MapRouteOverlay(
                id: "run-\(run.id)-leg",
                anchors: [originPt, stopPt],
                kind: loaded ? .loaded : .deadhead
            ))
            let progress = fraction(started: run.phaseStartedAt, ends: run.phaseEndsAt, clock: state.clock)
            return MapVehicleMarker(
                id: vehicle.id,
                displayCode: code,
                position: MapArc.point(originPt, stopPt, progress),
                headingRadians: MapArc.heading(originPt, stopPt, progress),
                isMoving: true,
                serviceProgress: nil,
                labelStackIndex: 0
            )

        case .servicing:
            let progress = fraction(started: run.phaseStartedAt, ends: run.phaseEndsAt, clock: state.clock)
            let isPickup: Bool
            switch route.stops[run.stopIndex].task {
            case .pickupShipment, .pickupContract, .loadFromWarehouse: isPickup = true
            default: isPickup = false
            }
            return MapVehicleMarker(
                id: vehicle.id,
                displayCode: code,
                position: stopPt,
                headingRadians: 0,
                isMoving: false,
                serviceProgress: isPickup ? progress : 1 - progress,
                labelStackIndex: 0
            )
        }
    }

    private static func fraction(started: GameTime, ends: GameTime, clock: GameTime) -> CGFloat {
        let total = max(1, started.minutes(until: ends))
        let elapsed = started.minutes(until: clock)
        return CGFloat(min(1, max(0, Double(elapsed) / Double(total))))
    }

    private static func placement(
        for job: ActiveJob,
        originPt: CGPoint,
        destPt: CGPoint,
        vehiclePt: CGPoint,
        progress: CGFloat
    ) -> (position: CGPoint, heading: CGFloat) {
        switch job.phase {
        case .loading:
            return (originPt, 0)
        case .unloading:
            return (destPt, 0)
        case .deadheading:
            return (MapArc.point(vehiclePt, originPt, progress), MapArc.heading(vehiclePt, originPt, progress))
        case .enRoute:
            return (MapArc.point(originPt, destPt, progress), MapArc.heading(originPt, destPt, progress))
        }
    }

    private static func fraction(of job: ActiveJob, clock: GameTime) -> CGFloat {
        let phaseMinutes = max(1, job.phaseStartedAt.minutes(until: job.phaseEndsAt))
        let elapsed = job.phaseStartedAt.minutes(until: clock)
        return CGFloat(min(1, max(0, Double(elapsed) / Double(phaseMinutes))))
    }
}
