//
//  GameMapScene+Camera.swift
//  Goods&Glory
//
//  Camera framing, pan/zoom gestures and hit testing — everything that
//  answers "where am I looking and what did I just touch".
//

import QuartzCore
import SpriteKit
import UIKit

extension GameMapScene {
    // MARK: - Camera and input

    func pan(by screenTranslation: CGPoint) {
        noteActivity()
        userMovedCamera = true
        cameraNode.position.x -= screenTranslation.x * cameraNode.xScale
        cameraNode.position.y += screenTranslation.y * cameraNode.yScale
        clampCamera()
    }

    /// Soft-pan to a city while keeping the current zoom level. `bottomInset`
    /// is screen space covered by chrome, so the city lands above it.
    func centerOnCity(_ cityID: CityID, bottomInset: CGFloat = 0, animated: Bool) {
        guard let city = catalog.city(cityID), size.width > 1, size.height > 1 else { return }
        noteActivity()
        userMovedCamera = true
        let point = projection.point(for: city)
        let halfWidth = size.width * cameraNode.xScale / 2
        let halfHeight = size.height * cameraNode.yScale / 2
        // Camera sits below the city by half the hidden band, which lifts the
        // city into the middle of the strip the player can still see.
        let biasY = -max(0, bottomInset) / 2 * cameraNode.yScale
        let target = CGPoint(
            x: clampedCenter(
                point.x,
                minimum: cameraBounds.minX,
                maximum: cameraBounds.maxX,
                halfViewport: halfWidth
            ),
            y: clampedCenter(
                point.y + biasY,
                minimum: cameraBounds.minY,
                maximum: cameraBounds.maxY,
                halfViewport: halfHeight
            )
        )
        cameraNode.removeAction(forKey: "cameraPan")
        guard animated else {
            cameraNode.position = target
            clampCamera()
            return
        }
        let move = SKAction.move(to: target, duration: 0.45)
        move.timingMode = .easeInEaseOut
        let finish = SKAction.run { [weak self] in
            self?.clampCamera()
        }
        cameraNode.run(.sequence([move, finish]), withKey: "cameraPan")
    }

    func zoom(by magnification: CGFloat, anchoredAt viewPoint: CGPoint) {
        guard magnification.isFinite, magnification > 0, view != nil else { return }
        noteActivity()
        userMovedCamera = true
        let worldBefore = convertPoint(fromView: viewPoint)
        let proposed = cameraNode.xScale / magnification
        setCameraScale(proposed.clamped(to: cameraScaleRange))
        let worldAfter = convertPoint(fromView: viewPoint)
        cameraNode.position.x += worldBefore.x - worldAfter.x
        cameraNode.position.y += worldBefore.y - worldAfter.y
        clampCamera()
    }

    func selectAt(viewPoint: CGPoint) {
        noteActivity()
        let scenePoint = convertPoint(fromView: viewPoint)
        let hitRadius = 34 * cameraNode.xScale
        let vehicleHitRadius = 28 * cameraNode.xScale

        // City wins over a truck parked / servicing on the same pin — tapping
        // the city marker must open the city, not the vehicle on top of it.
        var closestCity: (id: CityID, distance: CGFloat)?
        for city in catalog.cities {
            let point = projection.point(for: city)
            let distance = hypot(point.x - scenePoint.x, point.y - scenePoint.y)
            guard distance <= hitRadius else { continue }
            if closestCity == nil
                || distance < closestCity!.distance
                || (distance == closestCity!.distance && city.id.rawValue < closestCity!.id.rawValue) {
                closestCity = (city.id, distance)
            }
        }
        if let closestCity {
            onSelectionChanged?(.city(closestCity.id))
            return
        }

        var closestVehicle: (id: VehicleID, distance: CGFloat)?
        for (id, marker) in vehicleMarkers {
            let point = displayPosition(for: marker)
            let distance = hypot(point.x - scenePoint.x, point.y - scenePoint.y)
            guard distance <= vehicleHitRadius else { continue }
            if closestVehicle == nil
                || distance < closestVehicle!.distance
                || (distance == closestVehicle!.distance && id.rawValue < closestVehicle!.id.rawValue) {
                closestVehicle = (id, distance)
            }
        }
        if let closestVehicle {
            onSelectionChanged?(.vehicle(closestVehicle.id))
        } else {
            onSelectionChanged?(.none)
        }
    }

    /// Close enough to inspect operations, but never to street-map scale.
    private static let minZoomInRelativeToFit: CGFloat = 0.055
    /// The strategic surface is a game board; the whole board can be seen.
    private static let maxZoomOutRelativeToFit: CGFloat = 1.05

    var maxZoomOutScale: CGFloat {
        switch cameraFocus {
        case .route:
            // Route planning may span the whole network, so its fitted view is
            // allowed to pull farther back than the strategic live map.
            return max(0.3, fitScale * 1.05)
        case .world, .city, .free:
            return max(0.3, fitScale * Self.maxZoomOutRelativeToFit)
        }
    }

    var minZoomInScale: CGFloat {
        max(0.0867, fitScale * Self.minZoomInRelativeToFit)
    }

    var cameraScaleRange: ClosedRange<CGFloat> {
        minZoomInScale...maxZoomOutScale
    }

    /// Recompute fit metrics and place the camera for the active focus mode.
    func applyCameraFocus(animated: Bool) {
        guard size.width > 1, size.height > 1 else { return }

        // `.free` preserves whatever framing the player (or a prior focus) left.
        // On the very first layout it still falls through to the HQ opening frame.
        if case .free = cameraFocus, hasFittedCamera {
            clampCamera()
            return
        }

        fitScale = max(worldBounds.width / size.width, worldBounds.height / size.height) * 1.08

        let effectiveFocus: MapCameraFocus
        if case .free = cameraFocus {
            effectiveFocus = .world
        } else {
            effectiveFocus = cameraFocus
        }

        let target: (position: CGPoint, scale: CGFloat)
        switch effectiveFocus {
        case .free:
            return
        case .world:
            let center = hqCityID
                .flatMap(catalog.city)
                .map(projection.point(for:))
                ?? CGPoint(x: worldBounds.midX, y: worldBounds.midY)
            target = (
                center,
                (fitScale * 0.28).clamped(to: cameraScaleRange)
            )
        case .city(let cityID):
            if let city = catalog.city(cityID) {
                // Closest allowed zoom, city locked to viewport center.
                target = (projection.point(for: city), minZoomInScale)
            } else {
                target = (
                    CGPoint(x: worldBounds.midX, y: worldBounds.midY),
                    minZoomInScale
                )
            }
        case .route(let cityIDs, let topInset, let bottomInset):
            let points = cityIDs.compactMap { cityID in
                catalog.city(cityID).map(projection.point(for:))
            }
            if points.count == 1, let point = points.first {
                target = (point, minZoomInScale)
            } else if let bounds = Self.bounds(containing: points) {
                // Keep endpoints inside the visible band between top and bottom
                // chrome that overlays this map surface.
                let top = max(0, topInset)
                let bottom = max(0, bottomInset)
                let availableWidth = max(1, size.width - 56)
                let availableHeight = max(1, size.height - top - bottom)
                let fittedScale = max(
                    bounds.width / availableWidth,
                    bounds.height / availableHeight
                ) * 1.12
                let scale = fittedScale.clamped(to: cameraScaleRange)
                // Visible band center sits above the geometric screen center when
                // the bottom inset is larger than the top — bias the camera so the
                // leg is framed in that band instead of under the city card.
                let screenBiasY = (bottom - top) / 2
                let worldBiasY = -screenBiasY * scale
                target = (
                    CGPoint(x: bounds.midX, y: bounds.midY + worldBiasY),
                    scale
                )
            } else {
                let center = hqCityID
                    .flatMap(catalog.city)
                    .map(projection.point(for:))
                    ?? CGPoint(x: worldBounds.midX, y: worldBounds.midY)
                target = (center, minZoomInScale)
            }
        }

        let updates = {
            self.cameraNode.position = target.position
            self.setCameraScale(target.scale)
            self.clampCamera()
        }
        if animated {
            cameraNode.run(.group([
                .move(to: target.position, duration: 0.25),
                .scale(to: target.scale, duration: 0.25)
            ])) {
                self.setCameraScale(target.scale)
                self.clampCamera()
            }
        } else {
            updates()
        }
        hasFittedCamera = true
    }

    func setCameraScale(_ scale: CGFloat) {
        cameraNode.setScale(scale)
        activeRouteHaloNode.lineWidth = StrokeWidth.activeRouteHalo * scale
        activeRouteNode.lineWidth = StrokeWidth.activeRoute * scale
        plannedRouteNode.lineWidth = StrokeWidth.plannedRoute * scale
        landNode.lineWidth = StrokeWidth.landCoast * scale
        boundaryNode.lineWidth = StrokeWidth.boundary * scale

        for node in cityNodes.values { node.setScale(scale) }
        for node in plannedVisitNodes.values { node.setScale(scale) }
        for (id, node) in vehicleNodes {
            guard let marker = vehicleMarkers[id] else { continue }
            node.position = displayPosition(for: marker)
        }
        updateVehicleZoom()
        updateVehicleLabelStacks()
        updateSemanticZoom()
    }

    /// Applies the zoom-driven vehicle appearance to the whole fleet.
    func updateVehicleZoom() {
        let zoom = vehicleSemanticZoom(zoomOut: zoomOutAmount)
        let cameraScale = cameraNode.xScale
        for node in vehicleNodes.values {
            node.setSemanticZoom(
                cameraScale: cameraScale,
                semanticScale: zoom.scale,
                chassisAlpha: zoom.chassis,
                sparkAlpha: zoom.spark,
                labelAlpha: zoom.label
            )
        }
    }

    private static func bounds(containing points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }

    func clampCamera() {
        let halfWidth = size.width * cameraNode.xScale / 2
        let halfHeight = size.height * cameraNode.yScale / 2
        cameraNode.position.x = clampedCenter(
            cameraNode.position.x,
            minimum: cameraBounds.minX,
            maximum: cameraBounds.maxX,
            halfViewport: halfWidth
        )
        cameraNode.position.y = clampedCenter(
            cameraNode.position.y,
            minimum: cameraBounds.minY,
            maximum: cameraBounds.maxY,
            halfViewport: halfHeight
        )
    }

    func clampedCenter(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        halfViewport: CGFloat
    ) -> CGFloat {
        guard maximum - minimum > halfViewport * 2 else { return (minimum + maximum) / 2 }
        return value.clamped(to: (minimum + halfViewport)...(maximum - halfViewport))
    }

}
