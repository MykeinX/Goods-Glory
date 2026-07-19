//
//  GameMapScene.swift
//  Goods&Glory
//
//  SpriteKit owns only map presentation: batched static geography, camera,
//  selection and pooled vehicle sprites. Game rules and time remain in the
//  pure Swift domain and arrive here as MapRenderSnapshot values.
//

import QuartzCore
import SpriteKit
import UIKit

@MainActor
final class GameMapScene: SKScene {
    var onSelectionChanged: ((MapSelection) -> Void)?

    private let catalog: GameCatalog
    private let projection: MapProjection
    private let geography: MapGeographyDefinition
    private let cameraNode = SKCameraNode()

    private let terrainLayer = SKNode()
    private let routeLayer = SKNode()
    private let plannedRouteLayer = SKNode()
    private let cityLayer = SKNode()
    private let plannedVisitLayer = SKNode()
    private let vehicleLayer = SKNode()

    private let loadedRouteNode = SKShapeNode()
    private let deadheadRouteNode = SKShapeNode()
    private let plannedRouteNode = SKShapeNode()
    private let previewRouteNode = SKShapeNode()

    /// Fixed world-unit stroke widths (≈ km). Not scaled on zoom — avoids
    /// SKShapeNode retessellation during pinch gestures.
    private enum StrokeWidth {
        static let landCoast: CGFloat = 1
        static let waterCoast: CGFloat = 1
        /// Country borders, drawn at exactly the coastline's weight.
        ///
        /// The art direction (design/europe-map.js) draws the whole world as a
        /// single path — every country outline and every coast sharing one thin
        /// `#2B4463` stroke — which is what gives that map its flat, tiled,
        /// game-board character. Ours drew borders at more than twice the coast
        /// weight, so the continent read as one continuous landmass with heavy
        /// political lines scored across it: closer to an atlas than a board.
        static let boundary: CGFloat = 1
        static let loadedRoute: CGFloat = 4.5
        static let deadheadRoute: CGFloat = 3.5
        static let plannedRoute: CGFloat = 3
        static let previewRoute: CGFloat = 1.8
    }

    private var cityNodes: [CityID: MapCityNode] = [:]
    private var vehicleNodes: [VehicleID: MapVehicleNode] = [:]
    private var recycledVehicleNodes: [MapVehicleNode] = []
    private var vehicleMarkers: [VehicleID: MapVehicleMarker] = [:]
    private var lastRoutes: [MapRouteOverlay] = []
    private var plannedVisitNodes: [CityID: MapPlannedVisitNode] = [:]
    private var plannedVisitMarkers: [CityID: MapPlannedVisitMarker] = [:]
    private var lastPlannedVisits: [MapPlannedVisitMarker] = []
    private var idleFleetByCity: [CityID: Int] = [:]
    private var facilitiesByCity: [CityID: MapCityFacilities] = [:]
    private var attentionByCity: [CityID: MapCityAttention] = [:]

    /// Frame rates. The strategic map is mostly still: at 1x a vehicle covers a
    /// few points per second and most of the time nothing moves at all. Drawing
    /// an unchanged scene 30 times a second is pure heat, so the view drops to
    /// `idleFramesPerSecond` once nothing has happened for `idleDelay`.
    private enum FrameRate {
        static let active = 30
        static let idle = 8
        /// Grace period before sleeping, long enough to cover the gap between
        /// one-second simulation ticks without flapping.
        static let idleDelay: TimeInterval = 1.4
    }

    private var lastActivityAt: TimeInterval = 0
    private var isIdle = false

    private var hqCityID: CityID?
    private var selectedCityID: CityID?
    private var selectedVehicleID: VehicleID?
    private var highlightsStarterCities = false
    private var cameraFocus: MapCameraFocus = .world
    private var accentColor = UIColor.systemBlue
    private var fitScale: CGFloat = 1
    private var hasFittedCamera = false
    private var userMovedCamera = false

    private let worldBounds: CGRect
    private let cameraBounds: CGRect
    private let majorCityIDs: Set<CityID>
    private let regionalCityIDs: Set<CityID>

    init(catalog: GameCatalog, projection: MapProjection, geography: MapGeographyDefinition) {
        self.catalog = catalog
        self.projection = projection
        self.geography = geography
        let worldBounds = Self.makeWorldBounds(
            catalog: catalog,
            projection: projection,
            geography: geography
        )
        let navigationPadding = max(worldBounds.width, worldBounds.height) * 0.75
        self.worldBounds = worldBounds
        self.cameraBounds = worldBounds.insetBy(
            dx: -navigationPadding,
            dy: -navigationPadding
        )
        let citiesByPopulation = catalog.cities.sorted {
            $0.population == $1.population
                ? $0.id.rawValue < $1.id.rawValue
                : $0.population > $1.population
        }
        let majorCityCount = max(1, Int(ceil(Double(citiesByPopulation.count) * 0.2)))
        let regionalCityCount = max(majorCityCount, Int(ceil(Double(citiesByPopulation.count) * 0.6)))
        self.majorCityIDs = Set(citiesByPopulation.prefix(majorCityCount).map(\.id))
        self.regionalCityIDs = Set(citiesByPopulation.prefix(regionalCityCount).map(\.id))
        super.init(size: CGSize(width: 1, height: 1))
        scaleMode = .resizeFill
        backgroundColor = MapPalette.water
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        buildScene()
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        // Strategic map: 30 fps is the ceiling, not the resting rate.
        view.preferredFramesPerSecond = FrameRate.active
        noteActivity()
        if !hasFittedCamera { applyCameraFocus(animated: false) }
    }

    // MARK: - Idle throttling

    /// Something changed on screen: keep (or return to) the active frame rate.
    /// Called from every input, camera move and non-trivial snapshot apply.
    func noteActivity() {
        lastActivityAt = CACurrentMediaTime()
        guard isIdle else { return }
        isIdle = false
        view?.preferredFramesPerSecond = FrameRate.active
        setDecorativeAnimationsPaused(false)
    }

    override func update(_ currentTime: TimeInterval) {
        super.update(currentTime)
        guard !isIdle else { return }
        // Camera and vehicle actions are real motion; never sleep through them.
        guard !isAnimating else {
            lastActivityAt = CACurrentMediaTime()
            return
        }
        guard CACurrentMediaTime() - lastActivityAt > FrameRate.idleDelay else { return }
        isIdle = true
        view?.preferredFramesPerSecond = FrameRate.idle
        setDecorativeAnimationsPaused(true)
    }

    private var isAnimating: Bool {
        if cameraNode.hasActions() { return true }
        return vehicleNodes.values.contains { $0.hasActions() }
    }

    /// The HQ/starter halo pulse is a `repeatForever` action, so on its own it
    /// would keep the scene permanently busy. It sleeps with the map.
    private func setDecorativeAnimationsPaused(_ paused: Bool) {
        for node in cityNodes.values {
            node.setHaloPulsePaused(paused)
        }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if !userMovedCamera {
            applyCameraFocus(animated: false)
        } else {
            clampCamera()
        }
    }

    func configure(
        hqCityID: CityID?,
        selectedCityID: CityID?,
        selectedVehicleID: VehicleID?,
        highlightsStarterCities: Bool,
        accentColorHex: String,
        cameraFocus: MapCameraFocus
    ) {
        noteActivity()
        let framingChanged = self.cameraFocus != cameraFocus || self.hqCityID != hqCityID
        self.hqCityID = hqCityID
        self.selectedCityID = selectedCityID
        self.selectedVehicleID = selectedVehicleID
        self.highlightsStarterCities = highlightsStarterCities
        self.cameraFocus = cameraFocus
        self.accentColor = UIColor(hex: accentColorHex)
        loadedRouteNode.strokeColor = accentColor
        plannedRouteNode.strokeColor = accentColor.withAlphaComponent(0.78)
        previewRouteNode.strokeColor = accentColor.withAlphaComponent(0.7)
        updateCityStyles()
        updateVehicleStyles()
        updatePlannedVisitStyles()
        if framingChanged, size.width > 1, size.height > 1 {
            // Spot-job / route previews reframe. Returning to `.free` keeps the
            // camera where the player left it (including after leaving a preview).
            if case .free = cameraFocus, hasFittedCamera {
                // Keep current camera.
            } else {
                userMovedCamera = false
                applyCameraFocus(animated: true)
            }
        }
    }

    /// - Parameter animateVehicleMotion: When false, vehicles teleport to the
    ///   snapshot positions (used after the map wakes from a render pause so
    ///   off-tab simulation progress does not play back as a one-second rush).
    func apply(snapshot: MapRenderSnapshot, animateVehicleMotion: Bool = true) {
        if snapshot.routes != lastRoutes {
            lastRoutes = snapshot.routes
            rebuildRouteOverlays(snapshot.routes)
        }
        if snapshot.plannedVisits != lastPlannedVisits {
            lastPlannedVisits = snapshot.plannedVisits
            rebuildPlannedVisits(snapshot.plannedVisits)
        }
        // City chrome depends on these three dictionaries and nothing else. A
        // vehicle moving along an arc changes none of them, so restyling all
        // cities on every tick — each one re-measuring its label glyphs — was
        // work the player could never see.
        let cityChromeChanged = idleFleetByCity != snapshot.idleFleetByCity
            || facilitiesByCity != snapshot.facilitiesByCity
            || attentionByCity != snapshot.attentionByCity
        idleFleetByCity = snapshot.idleFleetByCity
        facilitiesByCity = snapshot.facilitiesByCity
        attentionByCity = snapshot.attentionByCity
        updateVehicles(snapshot.vehicles, animateMotion: animateVehicleMotion)
        if cityChromeChanged {
            updateCityStyles()
        }
        noteActivity()
    }

    // MARK: - Camera and input

    func pan(by screenTranslation: CGPoint) {
        noteActivity()
        userMovedCamera = true
        cameraNode.position.x -= screenTranslation.x * cameraNode.xScale
        cameraNode.position.y += screenTranslation.y * cameraNode.yScale
        clampCamera()
    }

    /// Soft-pan to a city while keeping the current zoom level.
    func centerOnCity(_ cityID: CityID, animated: Bool) {
        guard let city = catalog.city(cityID), size.width > 1, size.height > 1 else { return }
        noteActivity()
        userMovedCamera = true
        let point = projection.point(for: city)
        let halfWidth = size.width * cameraNode.xScale / 2
        let halfHeight = size.height * cameraNode.yScale / 2
        let target = CGPoint(
            x: clampedCenter(
                point.x,
                minimum: cameraBounds.minX,
                maximum: cameraBounds.maxX,
                halfViewport: halfWidth
            ),
            y: clampedCenter(
                point.y,
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
        guard magnification.isFinite, magnification > 0, let view else { return }
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
            return
        }

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
        } else {
            onSelectionChanged?(.none)
        }
    }

    /// Closest zoom relative to fit. Tightened in lockstep with the 0.40→0.32
    /// zoom-out trim (×0.8) so pinch range stays balanced.
    private static let minZoomInRelativeToFit: CGFloat = 0.0476
    /// Zoom-out cap relative to full-content fit. Below 1 so the whole world
    /// is never on screen at once (less clutter as the network grows).
    private static let maxZoomOutRelativeToFit: CGFloat = 0.32

    private var maxZoomOutScale: CGFloat {
        switch cameraFocus {
        case .route:
            // Route planning may span the whole network, so its fitted view is
            // allowed to pull farther back than the strategic live map.
            return max(0.3, fitScale * 1.05)
        case .world, .city, .free:
            return max(0.3, fitScale * Self.maxZoomOutRelativeToFit)
        }
    }

    private var minZoomInScale: CGFloat {
        max(0.102, fitScale * Self.minZoomInRelativeToFit)
    }

    private var cameraScaleRange: ClosedRange<CGFloat> {
        minZoomInScale...maxZoomOutScale
    }

    /// Recompute fit metrics and place the camera for the active focus mode.
    private func applyCameraFocus(animated: Bool) {
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
            let center: CGPoint
            if let hqCityID, let hq = catalog.city(hqCityID) {
                center = projection.point(for: hq)
            } else {
                center = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
            }
            // Strategic map opens at the closest allowed zoom, centered on HQ.
            target = (center, minZoomInScale)
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
        case .route(let cityIDs, let bottomInset):
            let points = cityIDs.compactMap { cityID in
                catalog.city(cityID).map(projection.point(for:))
            }
            if points.count == 1, let point = points.first {
                target = (point, minZoomInScale)
            } else if let bounds = Self.bounds(containing: points) {
                // Keep endpoints inside the visible band between the top status
                // chrome and the bottom city card / tab bar.
                let topInset: CGFloat = 130
                let bottom = max(126, bottomInset)
                let availableWidth = max(1, size.width - 72)
                let availableHeight = max(1, size.height - topInset - bottom)
                let fittedScale = max(
                    bounds.width / availableWidth,
                    bounds.height / availableHeight
                ) * 1.28
                let scale = fittedScale.clamped(to: cameraScaleRange)
                // Visible band center sits above the geometric screen center when
                // the bottom inset is larger than the top — bias the camera so the
                // leg is framed in that band instead of under the city card.
                let screenBiasY = (bottom - topInset) / 2
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

    private func setCameraScale(_ scale: CGFloat) {
        cameraNode.setScale(scale)
        // The preview contains only a handful of legs, so keeping it at a
        // stable screen-space weight is inexpensive and remains readable when
        // a continent-spanning route is fitted.
        plannedRouteNode.lineWidth = StrokeWidth.plannedRoute * scale
        previewRouteNode.lineWidth = StrokeWidth.previewRoute * scale

        for node in cityNodes.values { node.setScale(scale) }
        for node in plannedVisitNodes.values { node.setScale(scale) }
        for (id, node) in vehicleNodes {
            node.setScale(scale)
            if let marker = vehicleMarkers[id] {
                node.position = displayPosition(for: marker)
            }
        }
        updateSemanticZoom()
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

    private func clampCamera() {
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

    private func clampedCenter(
        _ value: CGFloat,
        minimum: CGFloat,
        maximum: CGFloat,
        halfViewport: CGFloat
    ) -> CGFloat {
        guard maximum - minimum > halfViewport * 2 else { return (minimum + maximum) / 2 }
        return value.clamped(to: (minimum + halfViewport)...(maximum - halfViewport))
    }

    // MARK: - Static scene

    private func buildScene() {
        camera = cameraNode
        addChild(cameraNode)

        terrainLayer.zPosition = 0
        routeLayer.zPosition = 20
        plannedRouteLayer.zPosition = 30
        cityLayer.zPosition = 40
        plannedVisitLayer.zPosition = 50
        vehicleLayer.zPosition = 60
        addChild(terrainLayer)
        addChild(routeLayer)
        addChild(plannedRouteLayer)
        addChild(cityLayer)
        addChild(plannedVisitLayer)
        addChild(vehicleLayer)

        addGeography()
        addCities()

        loadedRouteNode.strokeColor = accentColor
        loadedRouteNode.lineCap = .round
        loadedRouteNode.lineJoin = .round
        loadedRouteNode.lineWidth = StrokeWidth.loadedRoute
        loadedRouteNode.glowWidth = 0.5
        loadedRouteNode.zPosition = 2
        routeLayer.addChild(loadedRouteNode)

        deadheadRouteNode.strokeColor = MapPalette.deadhead
        deadheadRouteNode.lineCap = .round
        deadheadRouteNode.lineJoin = .round
        deadheadRouteNode.lineWidth = StrokeWidth.deadheadRoute
        deadheadRouteNode.zPosition = 1
        routeLayer.addChild(deadheadRouteNode)

        plannedRouteNode.strokeColor = accentColor.withAlphaComponent(0.78)
        plannedRouteNode.lineCap = .round
        plannedRouteNode.lineJoin = .round
        plannedRouteNode.lineWidth = StrokeWidth.plannedRoute
        plannedRouteNode.glowWidth = 1
        plannedRouteLayer.addChild(plannedRouteNode)

        previewRouteNode.strokeColor = accentColor.withAlphaComponent(0.7)
        previewRouteNode.lineCap = .round
        previewRouteNode.lineJoin = .round
        previewRouteNode.lineWidth = StrokeWidth.previewRoute
        previewRouteNode.glowWidth = 0
        previewRouteNode.zPosition = 0
        plannedRouteLayer.addChild(previewRouteNode)
    }

    /// Projected, simplified world silhouettes.
    ///
    /// The projection is a pure function of immutable catalog data and the
    /// simplification tolerances are constants, so every map surface in the app
    /// builds byte-identical paths. Building them once and handing out the same
    /// `CGPath` objects removes ~13,000 Mercator projections and a full
    /// Douglas–Peucker pass from every scene after the first — which is what
    /// opening the city detail or route builder screen used to pay for.
    @MainActor
    private enum TerrainPaths {
        /// Country borders read as national outlines at strategic zoom, not as
        /// surveyed cadastral lines. They are two thirds of all geography
        /// vertices, so this tolerance is the one worth being generous with.
        static let boundaryToleranceKm: CGFloat = 8

        static let cache = Cache()

        struct Built {
            let land: CGPath
            let boundaries: CGPath?
            let water: CGPath
        }

        final class Cache {
            private var built: Built?

            func paths(
                geography: MapGeographyDefinition,
                projection: MapProjection
            ) -> Built {
                if let built { return built }
                let value = Self.build(geography: geography, projection: projection)
                built = value
                return value
            }

            private static func build(
                geography: MapGeographyDefinition,
                projection: MapProjection
            ) -> Built {
                let landPath = CGMutablePath()
                for landMass in geography.landMasses where landMass.points.count >= 3 {
                    let points = MapPathSimplifier.simplifyClosed(
                        landMass.points.map(projection.point(for:))
                    )
                    guard points.count >= 3 else { continue }
                    landPath.addClosedPolyline(points)
                }

                let boundaryPath = CGMutablePath()
                var boundaryCount = 0
                for boundary in geography.boundaries where boundary.points.count >= 2 {
                    let points = MapPathSimplifier.simplify(
                        boundary.points.map(projection.point(for:)),
                        tolerance: boundaryToleranceKm
                    )
                    guard points.count >= 2 else { continue }
                    boundaryPath.addOpenPolyline(points)
                    boundaryCount += 1
                }

                let waterPath = CGMutablePath()
                for body in geography.waterBodies where body.points.count >= 3 {
                    let points = MapPathSimplifier.simplifyClosed(
                        body.points.map(projection.point(for:))
                    )
                    guard points.count >= 3 else { continue }
                    waterPath.addClosedPolyline(points)
                }

                return Built(
                    land: landPath,
                    boundaries: boundaryCount > 0 ? boundaryPath : nil,
                    water: waterPath
                )
            }
        }
    }

    private func addGeography() {
        let paths = TerrainPaths.cache.paths(geography: geography, projection: projection)

        let land = SKShapeNode(path: paths.land)
        land.fillColor = MapPalette.land
        land.strokeColor = MapPalette.coastline
        land.lineWidth = StrokeWidth.landCoast
        land.lineJoin = .round
        land.zPosition = 1
        terrainLayer.addChild(land)

        // Country borders: one static SKShapeNode (no per-zoom rebuild).
        if let boundaryPath = paths.boundaries {
            let borders = SKShapeNode(path: boundaryPath)
            borders.fillColor = .clear
            borders.strokeColor = MapPalette.boundary
            borders.lineWidth = StrokeWidth.boundary
            borders.lineCap = .round
            borders.lineJoin = .round
            borders.zPosition = 2
            terrainLayer.addChild(borders)
        }

        let water = SKShapeNode(path: paths.water)
        water.fillColor = MapPalette.water
        water.strokeColor = MapPalette.coastline
        water.lineWidth = StrokeWidth.waterCoast
        water.lineJoin = .round
        water.zPosition = 3
        terrainLayer.addChild(water)
    }

    private func addCities() {
        for city in catalog.cities {
            let node = MapCityNode(city: city)
            node.position = projection.point(for: city)
            cityLayer.addChild(node)
            cityNodes[city.id] = node
        }
        updateCityStyles()
    }

    // MARK: - Dynamic layers

    /// Draws live and planned routes as smooth city-to-city quadratic arcs.
    /// Planned geometry owns a separate layer so it cannot inherit live cargo
    /// or deadhead styling.
    private func rebuildRouteOverlays(_ overlays: [MapRouteOverlay]) {
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

    private func rebuildPlannedVisits(_ markers: [MapPlannedVisitMarker]) {
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

    private func updatePlannedVisitStyles() {
        for (cityID, node) in plannedVisitNodes {
            guard let marker = plannedVisitMarkers[cityID] else { continue }
            node.configure(marker: marker, accent: accentColor)
        }
    }

    private func updateVehicles(_ markers: [MapVehicleMarker], animateMotion: Bool) {
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
            node.setScale(cameraNode.xScale)
        }
    }

    private func updateVehicleStyles() {
        for (id, node) in vehicleNodes {
            guard let marker = vehicleMarkers[id] else { continue }
            node.apply(
                marker: marker,
                accent: accentColor,
                isSelected: id == selectedVehicleID,
                cameraScale: cameraNode.xScale
            )
        }
    }

    /// Loading/unloading stay on the city anchor; moving vehicles use interpolated arc points.
    private func displayPosition(for marker: MapVehicleMarker) -> CGPoint {
        marker.position
    }

    private func updateCityStyles() {
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
    private struct SemanticZoomKey: Equatable {
        let zoomStep: Int
        let selected: CityID?
        let hq: CityID?
        let highlightsStarters: Bool
    }

    private var lastSemanticZoomKey: SemanticZoomKey?

    private func updateSemanticZoom() {
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

    private enum CityImportance {
        case local
        case regional
        case major
    }

    /// 0 at closest zoom-in, 1 at the farthest allowed zoom-out.
    private var zoomOutAmount: CGFloat {
        let minScale = cameraScaleRange.lowerBound
        let maxScale = cameraScaleRange.upperBound
        let span = max(maxScale - minScale, 0.0001)
        return ((cameraNode.xScale - minScale) / span).clamped(to: 0...1)
    }

    /// Counter-scaled cities stay ~constant on screen unless this shrinks them
    /// as the camera pulls back — small dots at full zoom-out.
    private func markerScale(
        zoomOut: CGFloat,
        importance: CityImportance,
        isEmphasized: Bool
    ) -> CGFloat {
        let closeScale: CGFloat = isEmphasized ? 1.20 : 1.08
        let farScale: CGFloat
        switch importance {
        case .local: farScale = isEmphasized ? 0.42 : 0.32
        case .regional: farScale = isEmphasized ? 0.48 : 0.38
        case .major: farScale = isEmphasized ? 0.55 : 0.44
        }
        // Ease toward tiny dots in the second half of zoom-out.
        let t = smoothstep(((zoomOut - 0.08) / 0.92).clamped(to: 0...1))
        return closeScale + (farScale - closeScale) * t
    }

    /// Labels disappear small → large. At full zoom-out every name is gone.
    private func labelAlpha(
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

    private func smoothstep(_ t: CGFloat) -> CGFloat {
        t * t * (3 - 2 * t)
    }

    private static func makeWorldBounds(
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

// MARK: - Map nodes

@MainActor
private final class MapPlannedVisitNode: SKNode {
    private let marker = SKShapeNode(circleOfRadius: 13)
    private let stepLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let pickupBadge = SKShapeNode(circleOfRadius: 7.5)
    private let deliveryBadge = SKShapeNode(circleOfRadius: 7.5)
    private let pickupIcon = SKSpriteNode()
    private let deliveryIcon = SKSpriteNode()

    override init() {
        super.init()

        marker.fillColor = MapPalette.water
        marker.lineWidth = 2.2
        marker.zPosition = 1
        addChild(marker)

        stepLabel.fontSize = 9
        stepLabel.verticalAlignmentMode = .center
        stepLabel.horizontalAlignmentMode = .center
        stepLabel.position = CGPoint(x: 0, y: -0.5)
        stepLabel.zPosition = 2
        addChild(stepLabel)

        configureBadge(
            pickupBadge,
            icon: pickupIcon,
            symbol: "tray.and.arrow.up.fill"
        )
        configureBadge(
            deliveryBadge,
            icon: deliveryIcon,
            symbol: "tray.and.arrow.down.fill"
        )
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(marker value: MapPlannedVisitMarker, accent: UIColor) {
        let numberText = value.stepNumbers.map(String.init).joined(separator: "·")
        stepLabel.text = numberText
        stepLabel.fontSize = numberText.count > 4 ? 7 : (numberText.count > 2 ? 8 : 9)
        stepLabel.fontColor = accent
        marker.strokeColor = accent
        marker.glowWidth = 0.5

        pickupBadge.isHidden = !value.hasPickup
        deliveryBadge.isHidden = !value.hasDelivery
        pickupBadge.fillColor = accent
        pickupBadge.strokeColor = MapPalette.water
        deliveryBadge.fillColor = MapPalette.mint
        deliveryBadge.strokeColor = MapPalette.water
        pickupIcon.color = MapPalette.onBrand
        deliveryIcon.color = MapPalette.water

        let visibleBadges = [pickupBadge, deliveryBadge].filter { !$0.isHidden }
        if visibleBadges.count == 1 {
            visibleBadges[0].position = CGPoint(x: 0, y: -21)
        } else {
            pickupBadge.position = CGPoint(x: -9, y: -21)
            deliveryBadge.position = CGPoint(x: 9, y: -21)
        }
    }

    private func configureBadge(
        _ badge: SKShapeNode,
        icon: SKSpriteNode,
        symbol: String
    ) {
        badge.lineWidth = 1.2
        badge.zPosition = 3
        addChild(badge)

        icon.texture = Self.symbolTexture(named: symbol)
        icon.size = CGSize(width: 9, height: 9)
        icon.colorBlendFactor = 1
        icon.zPosition = 1
        badge.addChild(icon)
    }

    private static func symbolTexture(named name: String) -> SKTexture? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 10, weight: .black)
        guard let image = UIImage(
            systemName: name,
            withConfiguration: configuration
        )?.withTintColor(.white, renderingMode: .alwaysOriginal) else {
            return nil
        }
        return SKTexture(image: image)
    }
}

@MainActor
private final class MapCityNode: SKNode {
    private let markerContainer = SKNode()
    private let marker = SKShapeNode(circleOfRadius: 7)
    /// Design 1b HQ pin: rounded square filled with the company brand color.
    private let hqMarker = SKShapeNode(
        rect: CGRect(x: -8, y: -8, width: 16, height: 16),
        cornerRadius: 5
    )
    private let halo = SKShapeNode(circleOfRadius: 12)
    private let selectionRing = SKShapeNode(circleOfRadius: 10)
    private let labelRow = SKNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let fleetBadge = SKShapeNode(circleOfRadius: 7)
    private let fleetCount = SKLabelNode(fontNamed: "AvenirNext-Bold")
    /// Owned buildings, drawn as filled discs under the pin.
    private let facilityRow = SKNode()
    private let branchDisc = SKShapeNode(circleOfRadius: 7)
    private let warehouseDisc = SKShapeNode(circleOfRadius: 7)
    private let branchIcon = SKSpriteNode()
    private let warehouseIcon = SKSpriteNode()
    /// Freight needing attention. Colour carries the urgency; the number
    /// carries the volume. Everything else lives in the city screen.
    private let attentionBadge = SKShapeNode(circleOfRadius: 7)
    private let attentionCount = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let cityName: String

    init(city: CityDefinition) {
        cityName = city.name
        super.init()
        markerContainer.zPosition = 2
        addChild(markerContainer)

        marker.fillColor = MapPalette.city
        marker.strokeColor = MapPalette.cityStroke
        marker.lineWidth = 1.8
        marker.zPosition = 2
        markerContainer.addChild(marker)

        hqMarker.fillColor = MapPalette.gold
        hqMarker.strokeColor = MapPalette.water
        hqMarker.lineWidth = 1.5
        hqMarker.zPosition = 3
        hqMarker.isHidden = true
        markerContainer.addChild(hqMarker)

        halo.strokeColor = MapPalette.city
        halo.lineWidth = 1.5
        halo.fillColor = .clear
        halo.zPosition = 0
        halo.isHidden = true
        markerContainer.addChild(halo)

        selectionRing.strokeColor = .white
        selectionRing.lineWidth = 2
        selectionRing.fillColor = .clear
        selectionRing.zPosition = 1
        selectionRing.isHidden = true
        markerContainer.addChild(selectionRing)

        labelRow.zPosition = 4
        labelRow.position = CGPoint(x: 0, y: 11)
        addChild(labelRow)

        label.text = city.name
        label.fontSize = 11
        label.fontColor = MapPalette.label
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .left
        labelRow.addChild(label)

        fleetBadge.fillColor = MapPalette.gold
        fleetBadge.strokeColor = MapPalette.water
        fleetBadge.lineWidth = 1.2
        fleetBadge.zPosition = 1
        fleetBadge.isHidden = true
        labelRow.addChild(fleetBadge)

        // Baseline + left: frame ortası dairenin (0,0) noktasına taşınır (optik ortalama).
        fleetCount.fontSize = 9
        fleetCount.fontColor = MapPalette.water
        fleetCount.verticalAlignmentMode = .baseline
        fleetCount.horizontalAlignmentMode = .left
        fleetCount.zPosition = 2
        fleetBadge.addChild(fleetCount)

        attentionBadge.strokeColor = MapPalette.water
        attentionBadge.lineWidth = 1.2
        attentionBadge.zPosition = 1
        attentionBadge.isHidden = true
        labelRow.addChild(attentionBadge)

        attentionCount.fontSize = 9
        attentionCount.verticalAlignmentMode = .baseline
        attentionCount.horizontalAlignmentMode = .left
        attentionCount.zPosition = 2
        attentionBadge.addChild(attentionCount)

        // Facility strip sits below the pin so it never collides with the name.
        // Each building is a filled disc with a white glyph: at map scale a bare
        // tinted glyph reads as a smudge, a disc reads as a deliberate marker.
        facilityRow.zPosition = 5
        facilityRow.position = CGPoint(x: 0, y: -15)
        facilityRow.isHidden = true
        addChild(facilityRow)
        for (disc, icon, symbol) in [
            (branchDisc, branchIcon, "building.2.fill"),
            (warehouseDisc, warehouseIcon, "shippingbox.fill")
        ] {
            disc.lineWidth = 1.4
            disc.strokeColor = MapPalette.water
            disc.zPosition = 1
            disc.isHidden = true
            facilityRow.addChild(disc)

            icon.texture = Self.symbolTexture(named: symbol)
            icon.size = CGSize(width: 9, height: 9)
            icon.colorBlendFactor = 1
            icon.color = .white
            icon.zPosition = 2
            disc.addChild(icon)
        }

        layoutLabelRow()
    }

    /// Rendered at 3x and downscaled so the glyph stays crisp when the camera
    /// zooms in — a 9pt symbol rasterised at 9pt turns to mush.
    private static func symbolTexture(named name: String) -> SKTexture? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 27, weight: .heavy)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return nil }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Everything `configure` reads. Re-applying an identical appearance costs
    /// several SKShapeNode colour writes plus three SKLabelNode frame
    /// measurements (each a glyph layout), so identical input is skipped.
    private struct Appearance: Equatable {
        let isHQ: Bool
        let isStarter: Bool
        let isSelected: Bool
        let accent: UIColor
        let idleFleetCount: Int
        let facilities: MapCityFacilities?
        let attention: MapCityAttention?
    }

    private var appearance: Appearance?
    private var isPulseSuspended = false

    func configure(
        isHQ: Bool,
        isStarter: Bool,
        isSelected: Bool,
        accent: UIColor,
        idleFleetCount: Int,
        facilities: MapCityFacilities?,
        attention: MapCityAttention?
    ) {
        let next = Appearance(
            isHQ: isHQ,
            isStarter: isStarter,
            isSelected: isSelected,
            accent: accent,
            idleFleetCount: idleFleetCount,
            facilities: facilities,
            attention: attention
        )
        guard appearance != next else { return }
        appearance = next

        configureFacilityStrip(facilities, accent: accent)
        configureAttentionBadge(attention, isHQ: isHQ)
        marker.isHidden = isHQ
        hqMarker.isHidden = !isHQ
        if isHQ {
            hqMarker.fillColor = accent
            hqMarker.strokeColor = MapPalette.water
            halo.strokeColor = accent
        } else {
            let color = isStarter ? MapPalette.gold : MapPalette.city
            marker.fillColor = color
            marker.strokeColor = isStarter ? MapPalette.gold : MapPalette.cityStroke
            halo.strokeColor = color
        }
        halo.isHidden = !(isHQ || isStarter)
        selectionRing.isHidden = !isSelected
        selectionRing.strokeColor = isHQ ? accent : .white
        refreshHaloPulse()

        let showBadge = idleFleetCount > 0
        fleetBadge.isHidden = !showBadge
        fleetCount.isHidden = !showBadge
        if showBadge {
            fleetBadge.fillColor = accent
            fleetCount.fontColor = MapPalette.onBrand
            fleetCount.text = idleFleetCount > 9 ? "9+" : "\(idleFleetCount)"
        }
        layoutLabelRow()
    }

    private func configureFacilityStrip(_ facilities: MapCityFacilities?, accent: UIColor) {
        guard let facilities, facilities.hasBranch || facilities.hasWarehouse else {
            facilityRow.isHidden = true
            return
        }
        facilityRow.isHidden = false
        branchDisc.isHidden = !facilities.hasBranch
        warehouseDisc.isHidden = !facilities.hasWarehouse
        // Under construction reads as a dimmed marker: present, not yet yours.
        let alpha: CGFloat = facilities.isBuilding ? 0.5 : 1
        branchDisc.fillColor = accent
        branchDisc.alpha = alpha
        warehouseDisc.fillColor = MapPalette.mint
        warehouseDisc.alpha = alpha

        let visible = [branchDisc, warehouseDisc].filter { !$0.isHidden }
        if visible.count == 1 {
            visible[0].position = .zero
        } else {
            branchDisc.position = CGPoint(x: -8, y: 0)
            warehouseDisc.position = CGPoint(x: 8, y: 0)
        }
    }

    private func configureAttentionBadge(_ attention: MapCityAttention?, isHQ: Bool) {
        guard let attention, attention.total > 0 else {
            attentionBadge.isHidden = true
            return
        }
        attentionBadge.isHidden = false
        attentionBadge.fillColor = Self.urgencyColor(attention.urgency)
        attentionCount.fontColor = attention.urgency >= 0.5 ? .white : MapPalette.onBrand
        attentionCount.text = attention.total > 9 ? "9+" : "\(attention.total)"
    }

    /// Calm while there is time, hot as the delivery window runs out.
    private static func urgencyColor(_ urgency: Double) -> UIColor {
        if urgency >= 0.85 { return MapPalette.deadhead }
        if urgency >= 0.5 { return MapPalette.gold }
        return MapPalette.mint
    }

    /// Stops the halo's `repeatForever` pulse while the map sleeps. The action
    /// is removed rather than frozen so the halo rests at full opacity instead
    /// of sitting mid-fade for as long as the player leaves the map alone.
    func setHaloPulsePaused(_ paused: Bool) {
        guard isPulseSuspended != paused else { return }
        isPulseSuspended = paused
        refreshHaloPulse()
    }

    private func refreshHaloPulse() {
        guard !halo.isHidden, !isPulseSuspended else {
            halo.removeAction(forKey: "pulse")
            halo.alpha = 1
            halo.setScale(1)
            return
        }
        guard halo.action(forKey: "pulse") == nil else { return }
        halo.run(.repeatForever(.sequence([
            .group([.scale(to: 1.35, duration: 0.8), .fadeAlpha(to: 0.18, duration: 0.8)]),
            .group([.scale(to: 0.9, duration: 0), .fadeAlpha(to: 0.85, duration: 0)])
        ])), withKey: "pulse")
    }

    func setSemanticZoom(markerScale: CGFloat, markerAlpha: CGFloat, labelAlpha: CGFloat) {
        markerContainer.setScale(markerScale)
        markerContainer.alpha = markerAlpha
        labelRow.position.y = 8 + 7 * markerScale
        labelRow.setScale(max(0.55, 0.55 + 0.45 * labelAlpha))
        labelRow.alpha = labelAlpha
        labelRow.isHidden = labelAlpha < 0.02
        facilityRow.position.y = -8 - 6 * markerScale
        facilityRow.setScale(markerScale)
        facilityRow.alpha = markerAlpha
        // The attention badge is the one thing that must survive zoom-out: it
        // is the signal the player cannot afford to miss.
        if !attentionBadge.isHidden {
            labelRow.isHidden = false
            labelRow.alpha = max(labelAlpha, 0.9)
            label.alpha = labelAlpha
        } else {
            label.alpha = 1
        }
    }

    private func layoutLabelRow() {
        label.position = .zero
        // Gerçek glif kutusu: isim işaret altında ortalı kalsın.
        let nameFrame = label.frame
        if nameFrame.width > 1 {
            labelRow.position.x = -nameFrame.midX
        } else {
            labelRow.position.x = -(CGFloat(cityName.count) * 6.2) / 2
        }
        guard !fleetBadge.isHidden || !attentionBadge.isHidden else { return }

        let gap = label.fontSize * 0.12
        let badgeRadius: CGFloat = 7
        // Rozet merkezi, isim kutusunun dikey ortası ve sağ kenarı ile hizalı.
        let nameEndX = nameFrame.width > 1
            ? nameFrame.maxX
            : CGFloat(cityName.count) * 6.2
        let nameMidY = nameFrame.width > 1 ? nameFrame.midY : 0

        // Aksiyon rozeti isme en yakın konumda: en kritik bilgi en görünür yer.
        var cursorX = nameEndX + gap + badgeRadius
        if !attentionBadge.isHidden {
            attentionBadge.position = CGPoint(x: cursorX, y: nameMidY)
            cursorX += badgeRadius * 2 + gap
        }
        if !fleetBadge.isHidden {
            fleetBadge.position = CGPoint(x: cursorX, y: nameMidY)
        }

        // Rakam bounding box'unu dairenin merkezine kilitle.
        for counter in [fleetCount, attentionCount] {
            counter.position = .zero
            let digitFrame = counter.frame
            if digitFrame.width > 0.5, digitFrame.height > 0.5 {
                counter.position = CGPoint(x: -digitFrame.midX, y: -digitFrame.midY)
            }
        }
    }
}

private enum MapPalette {
    static let land = UIColor(red: 0.086, green: 0.157, blue: 0.247, alpha: 1)     // #16283F
    static let water = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 1)     // #0A1220
    /// One ink for every land edge, coast and border alike — the design draws
    /// them with a single stroke, so a faded coast would break the mosaic.
    static let coastline = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 1) // #2B4463
    /// Country borders — mockup uses the same `#2B4463` country stroke.
    static let boundary = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 1) // #2B4463
    static let city = UIColor(red: 0.122, green: 0.212, blue: 0.329, alpha: 1)      // #1F3654 fill
    static let cityStroke = UIColor(red: 0.478, green: 0.588, blue: 0.722, alpha: 1) // #7A96B8
    static let gold = UIColor(red: 1.0, green: 0.690, blue: 0.216, alpha: 1)         // #FFB037
    static let deadhead = UIColor(red: 1.0, green: 0.420, blue: 0.369, alpha: 0.85)  // #FF6B5E coral
    static let mint = UIColor(red: 0.310, green: 0.839, blue: 0.643, alpha: 1)       // #4FD6A4
    static let label = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.62)   // #F2EDE3
    static let onBrand = UIColor(red: 0.141, green: 0.082, blue: 0, alpha: 1)         // #241500
}

private final class MapVehicleNode: SKNode {
    private static let bodyRect = CGRect(x: -5.5, y: -3.5, width: 11, height: 7)
    private static let bodyCorner: CGFloat = 2.4

    private let selectionRing = SKShapeNode(circleOfRadius: 9)
    private let chassis = SKNode()
    /// Dim full capsule (empty / traveling base).
    private let body = SKShapeNode(
        rect: MapVehicleNode.bodyRect,
        cornerRadius: MapVehicleNode.bodyCorner
    )
    /// Loading/unloading fill that grows left → right inside the capsule.
    private let fillCrop = SKCropNode()
    private let fillBody = SKShapeNode(
        rect: MapVehicleNode.bodyRect,
        cornerRadius: MapVehicleNode.bodyCorner
    )
    private let fillMask = SKSpriteNode(color: .white, size: CGSize(width: 11, height: 7))
    private let outline = SKShapeNode(
        rect: MapVehicleNode.bodyRect,
        cornerRadius: MapVehicleNode.bodyCorner
    )
    private let labelBackground = SKShapeNode()
    private let label = SKLabelNode(fontNamed: "AvenirNext-Bold")

    override init() {
        super.init()
        selectionRing.fillColor = .clear
        selectionRing.lineWidth = 1.4
        selectionRing.alpha = 0
        selectionRing.zPosition = 0
        addChild(selectionRing)

        chassis.zPosition = 1
        addChild(chassis)

        body.fillColor = .white
        body.strokeColor = .clear
        body.lineWidth = 0
        body.zPosition = 0
        chassis.addChild(body)

        fillBody.fillColor = .white
        fillBody.strokeColor = .clear
        fillBody.lineWidth = 0
        fillCrop.addChild(fillBody)
        fillMask.anchorPoint = CGPoint(x: 0, y: 0.5)
        fillMask.position = CGPoint(x: Self.bodyRect.minX, y: 0)
        fillCrop.maskNode = fillMask
        fillCrop.zPosition = 1
        fillCrop.isHidden = true
        chassis.addChild(fillCrop)

        outline.fillColor = .clear
        outline.strokeColor = MapPalette.water
        outline.lineWidth = 1
        outline.zPosition = 2
        chassis.addChild(outline)

        labelBackground.fillColor = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 0.85)
        labelBackground.strokeColor = .clear
        labelBackground.zPosition = 2
        labelBackground.position = CGPoint(x: 0, y: 14)
        addChild(labelBackground)

        label.fontSize = 7.5
        label.fontColor = MapPalette.label.withAlphaComponent(0.92)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.zPosition = 3
        labelBackground.addChild(label)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        marker: MapVehicleMarker,
        accent: UIColor,
        isSelected: Bool,
        cameraScale: CGFloat
    ) {
        _ = cameraScale
        let heading = Self.stabilizedHeading(marker.headingRadians)
        if marker.isMoving {
            chassis.run(
                .rotate(
                    toAngle: heading,
                    duration: SimulationSpeed.clockTickSeconds,
                    shortestUnitArc: true
                ),
                withKey: "heading"
            )
        } else {
            chassis.removeAction(forKey: "heading")
            chassis.zRotation = heading
        }

        if let progress = marker.serviceProgress {
            let clamped = max(0, min(1, progress))
            body.fillColor = accent
            body.alpha = 0.18
            fillCrop.isHidden = false
            fillBody.fillColor = accent
            fillMask.size = CGSize(
                width: max(0.35, Self.bodyRect.width * CGFloat(clamped)),
                height: Self.bodyRect.height
            )
            outline.strokeColor = accent
        } else {
            fillCrop.isHidden = true
            body.fillColor = accent
            body.alpha = marker.isMoving ? 1 : 0.85
            outline.strokeColor = MapPalette.water
        }

        label.text = marker.displayCode
        label.fontColor = isSelected ? accent : MapPalette.label.withAlphaComponent(0.85)
        let textWidth = max(28, CGFloat(marker.displayCode.count) * 5.2 + 12)
        labelBackground.path = CGPath(
            roundedRect: CGRect(x: -textWidth / 2, y: -5.5, width: textWidth, height: 11),
            cornerWidth: 5.5,
            cornerHeight: 5.5,
            transform: nil
        )
        // Şehirdeyken isim, şehir adının üstünde; birden fazla araç dikey istiflenir.
        if marker.serviceProgress != nil {
            let baseY: CGFloat = 28
            let stackStep: CGFloat = 13
            labelBackground.position = CGPoint(
                x: 0,
                y: baseY + CGFloat(marker.labelStackIndex) * stackStep
            )
        } else {
            labelBackground.position = CGPoint(x: 0, y: 14)
        }

        selectionRing.strokeColor = accent
        selectionRing.alpha = isSelected ? 0.7 : 0
    }

    /// Keep heading in (-π, π] so shortest-arc rotates stay smooth across the ±π wrap.
    private static func stabilizedHeading(_ radians: CGFloat) -> CGFloat {
        var value = radians
        while value <= -.pi { value += 2 * .pi }
        while value > .pi { value -= 2 * .pi }
        return value
    }
}

private extension CGMutablePath {
    func addClosedPolyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
        closeSubpath()
    }

    func addOpenPolyline(_ points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() { addLine(to: point) }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension UIColor {
    convenience init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard Scanner(string: cleaned).scanHexInt64(&value), cleaned.count == 6 else {
            self.init(red: 0.12, green: 0.44, blue: 0.92, alpha: 1)
            return
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
