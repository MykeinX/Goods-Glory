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

    /// Draws live and planned routes as smooth city-to-city quadratic arcs.
    /// Planned geometry owns a separate layer so it cannot inherit live cargo
    /// or deadhead styling.
    func rebuildRouteOverlays(_ overlays: [MapRouteOverlay]) {
        let loaded = CGMutablePath()
        let deadhead = CGMutablePath()
        let planned = CGMutablePath()
        let preview = CGMutablePath()
        for overlay in overlays {
            let target: CGMutablePath
            switch overlay.kind {
            case .loaded: target = loaded
            case .deadhead: target = deadhead
            case .planned: target = planned
            case .preview: target = preview
            }
            // The adapter already produced the exact corridor polyline the
            // vehicles ride. Drawing anything else here — as the old quad-curve
            // reconstruction did — puts the truck beside its own route line.
            let anchors = overlay.anchors
            guard anchors.count >= 2 else { continue }
            target.addOpenPolyline(anchors)
        }
        loadedRouteNode.path = loaded
        // Dash the deadhead arc for the empty-return look.
        deadheadRouteNode.path = deadhead.copy(
            dashingWithPhase: 0,
            lengths: [StrokeWidth.deadheadRoute * 1.6, StrokeWidth.deadheadRoute * 2.4]
        )
        plannedRouteNode.path = planned
        previewRouteNode.path = preview.copy(
            dashingWithPhase: 0,
            lengths: [StrokeWidth.previewRoute * 2.2, StrokeWidth.previewRoute * 2.8]
        )
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
            if animateMotion, marker.isMoving, node.parent != nil, node.position != .zero {
                // Match the simulation tick window so motion fills the whole
                // second instead of a short burst followed by a visible pause.
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
    /// their capsules nest (~18%), not only when trucks share a pixel.
    func updateVehicleLabelStacks() {
        defer { updateVehicleZoom() }
        guard vehicleMarkers.count > 1 else {
            if let only = vehicleMarkers.first, only.value.labelStackIndex != 0 {
                applyLabelStack(id: only.key, stack: 0)
            }
            return
        }
        let zoom = vehicleSemanticZoom(zoomOut: zoomOutAmount)
        let nodeScale = cameraNode.xScale * zoom.scale
        let positions = vehicleMarkers.map { (id: $0.key, position: displayPosition(for: $0.value)) }
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
            serviceProgress: marker.serviceProgress,
            labelStackIndex: stack
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

    /// Inputs that decide every city's on-screen size and label opacity. Zoom is
    /// quantized so a pinch still reads as continuous while a still camera
    /// produces zero work.
    func updateSemanticZoom() {
        let zoomOut = zoomOutAmount
        let key = SemanticZoomKey(
            zoomStep: Int((zoomOut * 400).rounded()),
            selected: selectedCityID,
            hq: hqCityID,
            highlightsStarters: highlightsStarterCities
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
            cityNodes[city.id]?.setSemanticZoom(
                markerScale: markerScale(zoomOut: zoomOut, importance: importance, isEmphasized: isEmphasized),
                markerAlpha: 1,
                labelAlpha: labelAlpha(zoomOut: zoomOut, importance: importance, isEmphasized: isEmphasized)
            )
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

    /// Counter-scaled cities stay ~constant on screen unless this shrinks them
    /// as the camera pulls back — small dots at full zoom-out.
    func markerScale(
        zoomOut: CGFloat,
        importance: CityImportance,
        isEmphasized: Bool
    ) -> CGFloat {
        let closeScale: CGFloat = isEmphasized ? 1.20 : 1.08
        // Pulled well below the previous floor. Cities used to bottom out near
        // a third of their close size, which at full zoom-out still read as
        // buttons crowding the continent rather than points on it.
        let farScale: CGFloat
        switch importance {
        case .local: farScale = isEmphasized ? 0.22 : 0.14
        case .regional: farScale = isEmphasized ? 0.27 : 0.18
        case .major: farScale = isEmphasized ? 0.34 : 0.24
        }
        // Shrinking starts immediately and eases the whole way, so the map
        // opens out gradually instead of holding size and then collapsing.
        let t = smoothstep(zoomOut.clamped(to: 0...1))
        return closeScale + (farScale - closeScale) * t
    }

    /// Labels disappear small → large. At full zoom-out every name is gone.
    func labelAlpha(
        zoomOut: CGFloat,
        importance: CityImportance,
        isEmphasized: Bool
    ) -> CGFloat {
        let start: CGFloat
        let end: CGFloat
        if isEmphasized {
            // HQ / selection linger longest, but still clear by full zoom-out.
            start = 0.55
            end = 0.92
        } else {
            switch importance {
            case .local:
                start = 0.08
                end = 0.36
            case .regional:
                start = 0.28
                end = 0.58
            case .major:
                start = 0.45
                end = 0.78
            }
        }
        return 1 - smoothstep(((zoomOut - start) / max(end - start, 0.0001)).clamped(to: 0...1))
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
        geography: MapGeographyDefinition
    ) -> CGRect {
        // Borders are dense polylines; land/water already define the globe
        // extent, so skip them here to keep scene init cheap.
        let points = catalog.cities.map(projection.point(for:))
            + geography.landMasses.flatMap(\.points).map(projection.point(for:))
            + geography.waterBodies.flatMap(\.points).map(projection.point(for:))
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
