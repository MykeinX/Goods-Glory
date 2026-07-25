//
//  GameMapScene+Snapshot.swift
//  Goods&Glory
//
//  Applying a MapRenderSnapshot: routes, planned visits, city chrome and
//  pooled vehicle sprites.
//

import QuartzCore
import SpriteKit
import UIKit

extension GameMapScene {
    // MARK: - Dynamic layers

    /// Batches the deduplicated active network and planned lap into three shape
    /// nodes total (halo, road and preview), regardless of fleet size.
    func rebuildRouteOverlays(_ overlays: [MapRouteOverlay]) {
        let active = CGMutablePath()
        let planned = CGMutablePath()
        for overlay in overlays {
            let target: CGMutablePath
            switch overlay.kind {
            case .active: target = active
            case .planned: target = planned
            }
            let anchors = overlay.anchors
            guard anchors.count >= 2 else { continue }
            target.addOpenPolyline(anchors)
        }
        activeRouteHaloNode.path = active
        activeRouteNode.path = active
        activeRouteCoreNode.path = active
        plannedRouteNode.path = planned
    }

    func rebuildPlannedVisits(_ markers: [MapPlannedVisitMarker]) {
        for node in plannedVisitNodes.values {
            node.removeFromParent()
        }
        plannedVisitNodes = [:]
        plannedVisitMarkers = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })

        for marker in markers {
            let node = MapPlannedVisitNode()
            node.position = marker.position
            node.configure(marker: marker, accent: accentColor)
            node.setScale(cameraNode.xScale)
            plannedVisitLayer.addChild(node)
            plannedVisitNodes[marker.id] = node
        }
    }

    func updatePlannedVisitStyles() {
        for (cityID, node) in plannedVisitNodes {
            guard let marker = plannedVisitMarkers[cityID] else { continue }
            node.configure(marker: marker, accent: accentColor)
        }
    }

    func updateVehicles(_ markers: [MapVehicleMarker], animateMotion: Bool) {
        let nextIDs = Set(markers.map(\.id))
        for id in Array(vehicleNodes.keys) where !nextIDs.contains(id) {
            guard let node = vehicleNodes.removeValue(forKey: id) else { continue }
            node.removeAllActions()
            node.removeFromParent()
            recycledVehicleNodes.append(node)
            vehicleMarkers[id] = nil
        }

        for marker in markers {
            let previous = vehicleMarkers[marker.id]
            let node: MapVehicleNode
            if let existing = vehicleNodes[marker.id] {
                node = existing
            } else {
                node = recycledVehicleNodes.popLast() ?? MapVehicleNode()
                vehicleLayer.addChild(node)
                vehicleNodes[marker.id] = node
            }

            vehicleMarkers[marker.id] = marker
            node.apply(
                marker: marker,
                accent: accentColor,
                isSelected: marker.id == selectedVehicleID,
                cameraScale: cameraNode.xScale
            )
            let target = displayPosition(for: marker)
            // Ride the corridor rather than cutting to the next point. A tick
            // covers ten game minutes at 1x and sixty at 6x, so a straight
            // interpolation that is invisible at 1x drives visibly through the
            // land at 6x, corner by corner.
            if animateMotion, marker.isMoving, node.parent != nil, node.position != .zero,
               let corridor = marker.corridor,
               let previous, previous.corridor == corridor, previous.progress <= marker.progress {
                let from = previous.progress
                let span = marker.progress - from
                let duration = SimulationSpeed.clockTickSeconds
                let follow = SKAction.customAction(withDuration: duration) { node, elapsed in
                    let t = min(1, CGFloat(elapsed) / CGFloat(duration))
                    node.position = corridor.position(at: from + span * t)
                }
                node.run(follow, withKey: "movement")
            } else if animateMotion, marker.isMoving, node.parent != nil, node.position != .zero {
                // No shared corridor to follow — a vehicle that just changed
                // leg. Match the tick window so motion still fills the second.
                let move = SKAction.move(
                    to: target,
                    duration: SimulationSpeed.clockTickSeconds
                )
                move.timingMode = .linear
                node.run(move, withKey: "movement")
            } else {
                node.removeAction(forKey: "movement")
                node.position = target
            }
            node.setSparkColor(accentColor)
        }
        updateVehicleZoom()
        updateVehicleLabelStacks()
    }

    func updateVehicleStyles() {
        for (id, node) in vehicleNodes {
            guard let marker = vehicleMarkers[id] else { continue }
            node.apply(
                marker: marker,
                accent: accentColor,
                isSelected: id == selectedVehicleID,
                cameraScale: cameraNode.xScale
            )
            node.setSparkColor(accentColor)
        }
        updateVehicleZoom()
        updateVehicleLabelStacks()
    }

    /// Loading/unloading stay on the city anchor; moving vehicles use interpolated arc points.
    func displayPosition(for marker: MapVehicleMarker) -> CGPoint {
        marker.position
    }

    /// Restack name plates from live camera scale so labels lift as soon as
    /// their capsules overlap, not only when vehicles share an exact point.
    func updateVehicleLabelStacks() {
        defer { updateVehicleZoom() }
        guard vehicleMarkers.count > 1 else {
            if let only = vehicleMarkers.first, only.value.labelStackIndex != 0 {
                applyLabelStack(id: only.key, stack: 0)
            }
            return
        }
        let zoom = vehicleSemanticZoom(zoomOut: zoomOutAmount)
        // Nothing to lift apart while the plates are faded out, and this is
        // called on every camera frame — so a pinch out stops paying for it.
        guard zoom.label >= 0.02 else { return }
        let nodeScale = cameraNode.xScale * zoom.scale
        let positions = vehicleMarkers.map {
            (id: $0.key, position: displayPosition(for: $0.value))
        }
        let stacks = MapSceneAdapter.VehicleLabelStacking.indices(
            positions: positions,
            nodeScale: nodeScale
        )
        for (id, stack) in stacks {
            applyLabelStack(id: id, stack: stack)
        }
    }

    private func applyLabelStack(id: VehicleID, stack: Int) {
        guard let marker = vehicleMarkers[id], marker.labelStackIndex != stack else { return }
        let updated = MapVehicleMarker(
            id: marker.id,
            displayCode: marker.displayCode,
            position: marker.position,
            headingRadians: marker.headingRadians,
            isMoving: marker.isMoving,
            loadFraction: marker.loadFraction,
            serviceProgress: marker.serviceProgress,
            labelStackIndex: stack,
            corridor: marker.corridor,
            progress: marker.progress
        )
        vehicleMarkers[id] = updated
        guard let node = vehicleNodes[id] else { return }
        node.apply(
            marker: updated,
            accent: accentColor,
            isSelected: id == selectedVehicleID,
            cameraScale: cameraNode.xScale
        )
    }

    func updateCityStyles() {
        for city in catalog.cities {
            cityNodes[city.id]?.configure(
                isHQ: city.id == hqCityID,
                isStarter: highlightsStarterCities && city.isStarterCity,
                isSelected: city.id == selectedCityID,
                accent: accentColor,
                idleFleetCount: idleFleetByCity[city.id, default: 0],
                facilities: facilitiesByCity[city.id],
                attention: attentionByCity[city.id]
            )
        }
        updateSemanticZoom()
    }

    /// City pins are camera-counter-scaled (constant screen family) and then
    /// eased from night-dot to full stop as the player zooms in.
    ///
    /// Size and name visibility are applied separately on purpose. Size is a
    /// smooth function of the camera and is written every time it changes;
    /// running it through the zoom bucket below made pins step between sizes
    /// during a pinch. Which names to show depends on city importance and is
    /// far more expensive, so that part still refreshes per bucket.
    func updateSemanticZoom() {
        let zoomOut = zoomOutAmount
        let shrink = smoothstep(zoomOut.clamped(to: 0...1))
        // Stay near night-dot size through most of the pull-back; swell later.
        let closeScale: CGFloat = 1.15
        let farScale: CGFloat = 0.178
        let growth = pow(1.0 - shrink, 2.1)
        let markerScale = farScale + (closeScale - farScale) * growth
        for node in cityNodes.values {
            node.setMarkerScale(markerScale)
        }

        // Names stay readable into mid zoom-out; only near max pull-back they go.
        let labelVisibility = 1.0 - smoothstep(((zoomOut - 0.38) / 0.50).clamped(to: 0...1))

        let key = SemanticZoomKey(
            selected: selectedCityID,
            hq: hqCityID,
            highlightsStarters: highlightsStarterCities,
            zoomBucket: Int((zoomOut * 40).rounded())
        )
        guard key != lastSemanticZoomKey else { return }
        lastSemanticZoomKey = key

        for city in catalog.cities {
            let isEmphasized = city.id == selectedCityID
                || city.id == hqCityID
                || (highlightsStarterCities && city.isStarterCity)
            let importance: CityImportance
            if majorCityIDs.contains(city.id) {
                importance = .major
            } else if regionalCityIDs.contains(city.id) {
                importance = .regional
            } else {
                importance = .local
            }
            let hasGameplayState = idleFleetByCity[city.id, default: 0] > 0
                || facilitiesByCity[city.id] != nil
                || attentionByCity[city.id] != nil

            let showsLabelByImportance: Bool
            switch importance {
            case .major:
                showsLabelByImportance = true
            case .regional:
                showsLabelByImportance = zoomOut < 0.72
            case .local:
                showsLabelByImportance = zoomOut < 0.48
            }

            let labelAlpha: CGFloat
            if isEmphasized || hasGameplayState || showsLabelByImportance {
                labelAlpha = labelVisibility
            } else {
                labelAlpha = 0
            }

            cityNodes[city.id]?.setLabelVisibility(labelAlpha)
        }
    }

    enum CityImportance {
        case local
        case regional
        case major
    }

    /// 0 at closest zoom-in, 1 at the farthest allowed zoom-out.
    var zoomOutAmount: CGFloat {
        let minScale = cameraScaleRange.lowerBound
        let maxScale = cameraScaleRange.upperBound
        let span = max(maxScale - minScale, 0.0001)
        return ((cameraNode.xScale - minScale) / span).clamped(to: 0...1)
    }

    /// Vehicle appearance across the zoom range.
    ///
    /// Counter-scaling alone kept trucks a fixed size on screen, so pulling
    /// back turned the map into a field of identical capsules with no sense of
    /// distance. They now shrink with the world and, past the point where a
    /// truck silhouette stops being legible, become points of light instead.
    func vehicleSemanticZoom(zoomOut: CGFloat) -> (
        scale: CGFloat, chassis: CGFloat, spark: CGFloat, label: CGFloat
    ) {
        let shrink = smoothstep(zoomOut.clamped(to: 0...1))
        let scale = 1.0 + (0.34 - 1.0) * shrink

        // Hand-over window: the body fades out across the middle of the range
        // and the spark fades in behind it.
        let handover = smoothstep(((zoomOut - 0.34) / 0.30).clamped(to: 0...1))
        // Codes go first — a plate nobody can read is just noise on the lane.
        let labelFade = smoothstep(((zoomOut - 0.12) / 0.26).clamped(to: 0...1))
        return (scale, 1 - handover, handover, 1 - labelFade)
    }

    func smoothstep(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    // Called from GameMapScene.init — must be module-visible across files.
    static func makeWorldBounds(
        catalog: GameCatalog,
        projection: MapProjection,
        board: MapBoardSilhouette
    ) -> CGRect {
        // Camera fitting follows the authored game board, not detailed source
        // geography. This keeps the composition identical to the supplied art.
        let points = catalog.cities.map(projection.point(for:))
            + board.landMasses.flatMap(\.points).map(projection.point(for:))
        guard let first = points.first else { return CGRect(x: -100, y: -100, width: 200, height: 200) }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -90, dy: -90)
    }
}
