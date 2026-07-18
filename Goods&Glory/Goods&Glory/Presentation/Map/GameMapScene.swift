//
//  GameMapScene.swift
//  Goods&Glory
//
//  SpriteKit owns only map presentation: batched static geography, camera,
//  selection and pooled vehicle sprites. Game rules and time remain in the
//  pure Swift domain and arrive here as MapRenderSnapshot values.
//

import SpriteKit
import UIKit

@MainActor
final class GameMapScene: SKScene {
    var onCitySelected: ((CityID?) -> Void)?

    private let catalog: GameCatalog
    private let projection: MapProjection
    private let geography: MapGeographyDefinition
    private let cameraNode = SKCameraNode()

    private let terrainLayer = SKNode()
    private let routeLayer = SKNode()
    private let cityLayer = SKNode()
    private let vehicleLayer = SKNode()

    private let loadedRouteNode = SKShapeNode()
    private let deadheadRouteNode = SKShapeNode()

    /// Fixed world-unit stroke widths (≈ km). Not scaled on zoom — avoids
    /// SKShapeNode retessellation during pinch gestures.
    private enum StrokeWidth {
        static let landCoast: CGFloat = 1
        static let waterCoast: CGFloat = 1
        /// Country borders — same ink as mockup country strokes (`#2B4463`).
        /// Slightly thicker than coast so they read on land at strategic zoom.
        static let boundary: CGFloat = 2.2
        static let loadedRoute: CGFloat = 4.5
        static let deadheadRoute: CGFloat = 3.5
    }

    private var cityNodes: [CityID: MapCityNode] = [:]
    private var vehicleNodes: [VehicleID: SKSpriteNode] = [:]
    private var recycledVehicleNodes: [SKSpriteNode] = []
    private var vehicleMarkers: [VehicleID: MapVehicleMarker] = [:]
    private var lastRoutes: [MapRouteOverlay] = []

    private var hqCityID: CityID?
    private var selectedCityID: CityID?
    private var highlightsStarterCities = false
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
        // Strategic map: 30 fps is enough and keeps idle heat down on device.
        view.preferredFramesPerSecond = 30
        if !hasFittedCamera { fitCamera(animated: false) }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        if !userMovedCamera {
            fitCamera(animated: false)
        } else {
            clampCamera()
        }
    }

    func configure(
        hqCityID: CityID?,
        selectedCityID: CityID?,
        highlightsStarterCities: Bool,
        accentColorHex: String
    ) {
        self.hqCityID = hqCityID
        self.selectedCityID = selectedCityID
        self.highlightsStarterCities = highlightsStarterCities
        self.accentColor = UIColor(hex: accentColorHex)
        loadedRouteNode.strokeColor = accentColor
        updateCityStyles()
        for node in vehicleNodes.values {
            node.color = accentColor
        }
    }

    func apply(snapshot: MapRenderSnapshot) {
        if snapshot.routes != lastRoutes {
            lastRoutes = snapshot.routes
            rebuildActiveRoutes(snapshot.routes)
        }
        updateVehicles(snapshot.vehicles)
    }

    // MARK: - Camera and input

    func pan(by screenTranslation: CGPoint) {
        userMovedCamera = true
        cameraNode.position.x -= screenTranslation.x * cameraNode.xScale
        cameraNode.position.y += screenTranslation.y * cameraNode.yScale
        clampCamera()
    }

    func zoom(by magnification: CGFloat, anchoredAt viewPoint: CGPoint) {
        guard magnification.isFinite, magnification > 0, let view else { return }
        userMovedCamera = true
        let worldBefore = convertPoint(fromView: viewPoint)
        let proposed = cameraNode.xScale / magnification
        setCameraScale(proposed.clamped(to: cameraScaleRange))
        let worldAfter = convertPoint(fromView: viewPoint)
        cameraNode.position.x += worldBefore.x - worldAfter.x
        cameraNode.position.y += worldBefore.y - worldAfter.y
        clampCamera()
    }

    func selectCity(at viewPoint: CGPoint) {
        let scenePoint = convertPoint(fromView: viewPoint)
        let hitRadius = 34 * cameraNode.xScale
        var closest: (id: CityID, distance: CGFloat)?
        for city in catalog.cities {
            let point = projection.point(for: city)
            let distance = hypot(point.x - scenePoint.x, point.y - scenePoint.y)
            guard distance <= hitRadius else { continue }
            if closest == nil
                || distance < closest!.distance
                || (distance == closest!.distance && city.id.rawValue < closest!.id.rawValue) {
                closest = (city.id, distance)
            }
        }
        onCitySelected?(closest?.id)
    }

    /// Zoom-out cap relative to full-content fit. Below 1 so the whole world
    /// is never on screen at once (less clutter as the network grows).
    private static let maxZoomOutRelativeToFit: CGFloat = 0.5

    private var maxZoomOutScale: CGFloat {
        max(0.3, fitScale * Self.maxZoomOutRelativeToFit)
    }

    private var cameraScaleRange: ClosedRange<CGFloat> {
        // Zoom-in: ~14× closer than fit. Zoom-out: 0.5× fit.
        max(0.15, fitScale * 0.07)...maxZoomOutScale
    }

    private func fitCamera(animated: Bool) {
        guard size.width > 1, size.height > 1 else { return }
        fitScale = max(worldBounds.width / size.width, worldBounds.height / size.height) * 1.08
        let targetScale = maxZoomOutScale
        let updates = {
            self.cameraNode.position = CGPoint(x: self.worldBounds.midX, y: self.worldBounds.midY)
            self.setCameraScale(targetScale)
        }
        if animated {
            cameraNode.run(.group([
                .move(to: CGPoint(x: worldBounds.midX, y: worldBounds.midY), duration: 0.25),
                .scale(to: targetScale, duration: 0.25)
            ]))
        } else {
            updates()
        }
        hasFittedCamera = true
    }

    private func setCameraScale(_ scale: CGFloat) {
        cameraNode.setScale(scale)

        for node in cityNodes.values { node.setScale(scale) }
        for (id, node) in vehicleNodes {
            node.setScale(scale)
            if let marker = vehicleMarkers[id] {
                node.position = displayPosition(for: marker, cameraScale: scale)
            }
        }
        updateSemanticZoom()
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
        cityLayer.zPosition = 40
        vehicleLayer.zPosition = 60
        addChild(terrainLayer)
        addChild(routeLayer)
        addChild(cityLayer)
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
    }

    private func addGeography() {
        let landPath = CGMutablePath()
        for landMass in geography.landMasses where landMass.points.count >= 3 {
            let points = MapPathSimplifier.simplifyClosed(
                landMass.points.map(projection.point(for:))
            )
            guard points.count >= 3 else { continue }
            landPath.addClosedPolyline(points)
        }
        let land = SKShapeNode(path: landPath)
        land.fillColor = MapPalette.land
        land.strokeColor = MapPalette.coastline
        land.lineWidth = StrokeWidth.landCoast
        land.lineJoin = .round
        land.zPosition = 1
        terrainLayer.addChild(land)

        // Country borders: one static SKShapeNode (no per-zoom rebuild).
        let boundaryPath = CGMutablePath()
        var boundaryCount = 0
        for boundary in geography.boundaries where boundary.points.count >= 2 {
            let points = MapPathSimplifier.simplify(
                boundary.points.map(projection.point(for:)),
                tolerance: 2
            )
            guard points.count >= 2 else { continue }
            boundaryPath.addOpenPolyline(points)
            boundaryCount += 1
        }
        if boundaryCount > 0 {
            let borders = SKShapeNode(path: boundaryPath)
            borders.fillColor = .clear
            borders.strokeColor = MapPalette.boundary
            borders.lineWidth = StrokeWidth.boundary
            borders.lineCap = .round
            borders.lineJoin = .round
            borders.zPosition = 2
            terrainLayer.addChild(borders)
        }

        let waterPath = CGMutablePath()
        for body in geography.waterBodies where body.points.count >= 3 {
            let points = MapPathSimplifier.simplifyClosed(
                body.points.map(projection.point(for:))
            )
            guard points.count >= 3 else { continue }
            waterPath.addClosedPolyline(points)
        }
        let water = SKShapeNode(path: waterPath)
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

    /// Draws each active route as a smooth city-to-city quadratic arc, matching
    /// the design's stylized network (no road-following polylines).
    private func rebuildActiveRoutes(_ overlays: [MapRouteOverlay]) {
        let loaded = CGMutablePath()
        let deadhead = CGMutablePath()
        for overlay in overlays {
            let target = overlay.kind == .loaded ? loaded : deadhead
            let anchors = overlay.anchors
            guard anchors.count >= 2 else { continue }
            for index in 0..<(anchors.count - 1) {
                let a = anchors[index]
                let b = anchors[index + 1]
                target.move(to: a)
                target.addQuadCurve(to: b, control: MapArc.control(a, b))
            }
        }
        loadedRouteNode.path = loaded
        // Dash the deadhead arc for the empty-return look.
        deadheadRouteNode.path = deadhead.copy(
            dashingWithPhase: 0,
            lengths: [StrokeWidth.deadheadRoute * 1.6, StrokeWidth.deadheadRoute * 2.4]
        )
    }

    private func updateVehicles(_ markers: [MapVehicleMarker]) {
        let nextIDs = Set(markers.map(\.id))
        for id in Array(vehicleNodes.keys) where !nextIDs.contains(id) {
            guard let node = vehicleNodes.removeValue(forKey: id) else { continue }
            node.removeAllActions()
            node.removeFromParent()
            recycledVehicleNodes.append(node)
            vehicleMarkers[id] = nil
        }

        for marker in markers {
            let node: SKSpriteNode
            if let existing = vehicleNodes[marker.id] {
                node = existing
            } else {
                node = recycledVehicleNodes.popLast() ?? makeVehicleNode()
                node.color = accentColor
                vehicleLayer.addChild(node)
                vehicleNodes[marker.id] = node
            }

            vehicleMarkers[marker.id] = marker
            let target = displayPosition(for: marker, cameraScale: cameraNode.xScale)
            if marker.isMoving, node.parent != nil, node.position != .zero {
                node.run(.move(to: target, duration: 0.28), withKey: "movement")
                node.run(.rotate(toAngle: marker.headingRadians, duration: 0.18, shortestUnitArc: true), withKey: "heading")
            } else {
                node.removeAction(forKey: "movement")
                node.position = target
                node.zRotation = marker.headingRadians
            }
            node.alpha = marker.isMoving ? 1 : 0.82
            node.setScale(cameraNode.xScale)
        }
    }

    private func makeVehicleNode() -> SKSpriteNode {
        let node = SKSpriteNode(texture: MapVehicleTexture.shared)
        node.size = CGSize(width: 22, height: 14)
        node.colorBlendFactor = 1
        node.color = accentColor
        node.zPosition = 1
        return node
    }

    private func displayPosition(for marker: MapVehicleMarker, cameraScale: CGFloat) -> CGPoint {
        guard !marker.isMoving else { return marker.position }
        let column = marker.stackIndex % 3
        let row = marker.stackIndex / 3
        return CGPoint(
            x: marker.position.x + CGFloat(18 + column * 14) * cameraScale,
            y: marker.position.y - CGFloat(15 + row * 12) * cameraScale
        )
    }

    private func updateCityStyles() {
        for city in catalog.cities {
            cityNodes[city.id]?.configure(
                isHQ: city.id == hqCityID,
                isStarter: highlightsStarterCities && city.isStarterCity,
                isSelected: city.id == selectedCityID,
                accent: accentColor
            )
        }
        updateSemanticZoom()
    }

    private func updateSemanticZoom() {
        let relativeScale = cameraNode.xScale / max(fitScale, 0.001)
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
                markerScale: markerScale(relativeScale: relativeScale, importance: importance),
                markerAlpha: markerAlpha(
                    relativeScale: relativeScale,
                    importance: importance,
                    isEmphasized: isEmphasized
                ),
                labelAlpha: labelAlpha(
                    relativeScale: relativeScale,
                    importance: importance,
                    isEmphasized: isEmphasized
                )
            )
        }
    }

    private enum CityImportance {
        case local
        case regional
        case major
    }

    /// Relative scale is 1 when the whole map is fitted. Values below 1 are
    /// closer zoom levels; values above 1 are strategic, zoomed-out levels.
    private func markerScale(relativeScale: CGFloat, importance: CityImportance) -> CGFloat {
        let zoomInProgress = ((0.75 - relativeScale) / 0.55).clamped(to: 0...1)
        let zoomOutProgress = ((relativeScale - 0.75) / 1.25).clamped(to: 0...1)
        let importanceAdjustment: CGFloat
        switch importance {
        case .local: importanceAdjustment = -0.10
        case .regional: importanceAdjustment = 0
        case .major: importanceAdjustment = 0.08
        }
        return 1 + zoomInProgress * 0.25
            - zoomOutProgress * 0.38
            + zoomOutProgress * importanceAdjustment
    }

    private func markerAlpha(
        relativeScale: CGFloat,
        importance: CityImportance,
        isEmphasized: Bool
    ) -> CGFloat {
        let zoomOutProgress = ((relativeScale - 0.75) / 1.25).clamped(to: 0...1)
        let maximumFade: CGFloat
        switch importance {
        case .local: maximumFade = 0.55
        case .regional: maximumFade = 0.34
        case .major: maximumFade = 0.16
        }
        let baseAlpha = 1 - zoomOutProgress * maximumFade
        return isEmphasized ? max(baseAlpha, 0.88) : baseAlpha
    }

    private func labelAlpha(
        relativeScale: CGFloat,
        importance: CityImportance,
        isEmphasized: Bool
    ) -> CGFloat {
        if isEmphasized {
            return fadeOutAlpha(relativeScale, startsAt: 1.20, endsAt: 1.85)
        }
        switch importance {
        case .local:
            return fadeOutAlpha(relativeScale, startsAt: 0.28, endsAt: 0.52)
        case .regional:
            return fadeOutAlpha(relativeScale, startsAt: 0.48, endsAt: 0.86)
        case .major:
            return fadeOutAlpha(relativeScale, startsAt: 0.82, endsAt: 1.48)
        }
    }

    private func fadeOutAlpha(
        _ value: CGFloat,
        startsAt start: CGFloat,
        endsAt end: CGFloat
    ) -> CGFloat {
        let progress = ((value - start) / (end - start)).clamped(to: 0...1)
        let smoothProgress = progress * progress * (3 - 2 * progress)
        return 1 - smoothProgress
    }

    private static func makeWorldBounds(
        catalog: GameCatalog,
        projection: MapProjection,
        geography: MapGeographyDefinition
    ) -> CGRect {
        // Borders are dense polylines; land/water already define the globe
        // extent, so skip them here to keep scene init cheap.
        let points = catalog.roads.flatMap(\.geometry).map(projection.point(for:))
            + catalog.cities.map(projection.point(for:))
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
private final class MapCityNode: SKNode {
    private let markerContainer = SKNode()
    private let marker = SKShapeNode(circleOfRadius: 7)
    private let halo = SKShapeNode(circleOfRadius: 12)
    private let selectionRing = SKShapeNode(circleOfRadius: 10)
    private let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")

    init(city: CityDefinition) {
        super.init()
        markerContainer.zPosition = 2
        addChild(markerContainer)

        marker.fillColor = MapPalette.city
        marker.strokeColor = MapPalette.cityStroke
        marker.lineWidth = 1.8
        marker.zPosition = 2
        markerContainer.addChild(marker)

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

        label.text = city.name
        label.fontSize = 11
        label.fontColor = MapPalette.label
        label.verticalAlignmentMode = .bottom
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 11)
        label.zPosition = 4
        addChild(label)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(isHQ: Bool, isStarter: Bool, isSelected: Bool, accent: UIColor) {
        let color = isHQ ? accent : (isStarter ? MapPalette.gold : MapPalette.city)
        marker.fillColor = color
        halo.strokeColor = color
        halo.isHidden = !(isHQ || isStarter)
        selectionRing.isHidden = !isSelected
        if halo.isHidden {
            halo.removeAllActions()
            halo.alpha = 1
            halo.setScale(1)
        } else if halo.action(forKey: "pulse") == nil {
            halo.run(.repeatForever(.sequence([
                .group([.scale(to: 1.35, duration: 0.8), .fadeAlpha(to: 0.18, duration: 0.8)]),
                .group([.scale(to: 0.9, duration: 0), .fadeAlpha(to: 0.85, duration: 0)])
            ])), withKey: "pulse")
        }
    }

    func setSemanticZoom(markerScale: CGFloat, markerAlpha: CGFloat, labelAlpha: CGFloat) {
        markerContainer.setScale(markerScale)
        markerContainer.alpha = markerAlpha
        label.position.y = 8 + 7 * markerScale
        label.alpha = labelAlpha
        label.isHidden = labelAlpha < 0.01
    }
}

private enum MapVehicleTexture {
    static let shared: SKTexture = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 28))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            let body = UIBezierPath(roundedRect: CGRect(x: 3, y: 8, width: 25, height: 12), cornerRadius: 3)
            body.fill()
            let cabin = UIBezierPath()
            cabin.move(to: CGPoint(x: 28, y: 11))
            cabin.addLine(to: CGPoint(x: 35, y: 11))
            cabin.addLine(to: CGPoint(x: 40, y: 17))
            cabin.addLine(to: CGPoint(x: 40, y: 20))
            cabin.addLine(to: CGPoint(x: 28, y: 20))
            cabin.close()
            cabin.fill()
            cg.fillEllipse(in: CGRect(x: 9, y: 18, width: 7, height: 7))
            cg.fillEllipse(in: CGRect(x: 31, y: 18, width: 7, height: 7))
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }()
}

private enum MapPalette {
    static let land = UIColor(red: 0.086, green: 0.157, blue: 0.247, alpha: 1)     // #16283F
    static let water = UIColor(red: 0.039, green: 0.071, blue: 0.125, alpha: 1)     // #0A1220
    static let coastline = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 0.85) // #2B4463
    /// Country borders — mockup uses the same `#2B4463` country stroke.
    static let boundary = UIColor(red: 0.169, green: 0.267, blue: 0.388, alpha: 1) // #2B4463
    static let city = UIColor(red: 0.122, green: 0.212, blue: 0.329, alpha: 1)      // #1F3654 fill
    static let cityStroke = UIColor(red: 0.478, green: 0.588, blue: 0.722, alpha: 1) // #7A96B8
    static let gold = UIColor(red: 1.0, green: 0.690, blue: 0.216, alpha: 1)         // #FFB037
    static let deadhead = UIColor(red: 1.0, green: 0.420, blue: 0.369, alpha: 0.85)  // #FF6B5E coral
    static let label = UIColor(red: 0.949, green: 0.929, blue: 0.886, alpha: 0.62)   // #F2EDE3
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
