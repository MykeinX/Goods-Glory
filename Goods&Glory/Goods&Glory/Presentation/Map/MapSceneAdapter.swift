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

struct MapVehicleMarker: Identifiable, Equatable {
    let id: VehicleID
    let position: CGPoint
    let headingRadians: CGFloat
    let isMoving: Bool
    /// Stable screen-space separation for vehicles parked at the same city.
    let stackIndex: Int
}

enum MapRouteKind: Hashable {
    case loaded
    case deadhead
}

struct MapRouteOverlay: Identifiable, Equatable {
    let id: String
    /// Ordered city anchor points; consecutive pairs are joined by a quad arc.
    let anchors: [CGPoint]
    let kind: MapRouteKind
}

struct MapRenderSnapshot: Equatable {
    let vehicles: [MapVehicleMarker]
    let routes: [MapRouteOverlay]

    static let empty = MapRenderSnapshot(vehicles: [], routes: [])
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
        projection: MapProjection
    ) -> MapRenderSnapshot {
        var markers: [MapVehicleMarker] = []
        var routes: [MapRouteOverlay] = []
        var idleCountPerCity: [CityID: Int] = [:]

        func point(_ id: CityID) -> CGPoint {
            catalog.city(id).map(projection.point(for:)) ?? .zero
        }

        // Sorted by ID so same-city stacking offsets remain deterministic.
        for vehicle in state.vehicles.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            guard let job = state.activeJob(for: vehicle.id) else {
                guard let city = catalog.city(vehicle.cityID) else { continue }
                let stackIndex = idleCountPerCity[vehicle.cityID, default: 0]
                idleCountPerCity[vehicle.cityID] = stackIndex + 1
                markers.append(MapVehicleMarker(
                    id: vehicle.id,
                    position: projection.point(for: city),
                    headingRadians: 0,
                    isMoving: false,
                    stackIndex: stackIndex
                ))
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

            let placement = placement(
                for: job,
                originPt: originPt,
                destPt: destPt,
                vehiclePt: vehiclePt,
                clock: state.clock
            )
            markers.append(MapVehicleMarker(
                id: vehicle.id,
                position: placement.position,
                headingRadians: placement.heading,
                isMoving: job.phase == .deadheading || job.phase == .enRoute,
                stackIndex: 0
            ))
        }
        return MapRenderSnapshot(vehicles: markers, routes: routes)
    }

    private static func placement(
        for job: ActiveJob,
        originPt: CGPoint,
        destPt: CGPoint,
        vehiclePt: CGPoint,
        clock: GameTime
    ) -> (position: CGPoint, heading: CGFloat) {
        switch job.phase {
        case .loading:
            return (originPt, 0)
        case .unloading:
            return (destPt, 0)
        case .deadheading:
            let t = fraction(of: job, clock: clock)
            return (MapArc.point(vehiclePt, originPt, t), MapArc.heading(vehiclePt, originPt, t))
        case .enRoute:
            let t = fraction(of: job, clock: clock)
            return (MapArc.point(originPt, destPt, t), MapArc.heading(originPt, destPt, t))
        }
    }

    private static func fraction(of job: ActiveJob, clock: GameTime) -> CGFloat {
        let phaseMinutes = max(1, job.phaseStartedAt.minutes(until: job.phaseEndsAt))
        let elapsed = job.phaseStartedAt.minutes(until: clock)
        return CGFloat(min(1, max(0, Double(elapsed) / Double(phaseMinutes))))
    }
}
