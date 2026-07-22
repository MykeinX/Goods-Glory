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

    let catalog: GameCatalog
    let projection: MapProjection
    let geography: MapGeographyDefinition
    let cameraNode = SKCameraNode()

    let terrainLayer = SKNode()
    let routeLayer = SKNode()
    let plannedRouteLayer = SKNode()
    let cityLayer = SKNode()
    let plannedVisitLayer = SKNode()
    let vehicleLayer = SKNode()

    let loadedRouteNode = SKShapeNode()
    let deadheadRouteNode = SKShapeNode()
    let plannedRouteNode = SKShapeNode()
    let previewRouteNode = SKShapeNode()

    /// Fixed world-unit stroke widths (≈ km). Not scaled on zoom — avoids
    /// SKShapeNode retessellation during pinch gestures.
    enum StrokeWidth {
        static let landCoast: CGFloat = 1
        static let waterCoast: CGFloat = 1
        /// Country borders. Slightly heavier than the coastline, with a soft
        /// halo underneath — a 1 px hairline sparkles under pinch-zoom; a
        /// soft dual stroke stays readable without reading as atlas ink.
        static let boundary: CGFloat = 2
        static let boundaryHalo: CGFloat = 4.5
        static let loadedRoute: CGFloat = 4.5
        static let deadheadRoute: CGFloat = 3.5
        static let plannedRoute: CGFloat = 3
        static let previewRoute: CGFloat = 1.8
    }

    var cityNodes: [CityID: MapCityNode] = [:]
    var vehicleNodes: [VehicleID: MapVehicleNode] = [:]
    var recycledVehicleNodes: [MapVehicleNode] = []
    var vehicleMarkers: [VehicleID: MapVehicleMarker] = [:]
    var lastRoutes: [MapRouteOverlay] = []
    var plannedVisitNodes: [CityID: MapPlannedVisitNode] = [:]
    var plannedVisitMarkers: [CityID: MapPlannedVisitMarker] = [:]
    var lastPlannedVisits: [MapPlannedVisitMarker] = []
    var idleFleetByCity: [CityID: Int] = [:]
    var facilitiesByCity: [CityID: MapCityFacilities] = [:]
    var attentionByCity: [CityID: MapCityAttention] = [:]

    /// Frame rates. The strategic map is mostly still: at 1x a vehicle covers a
    /// few points per second and most of the time nothing moves at all. Drawing
    /// an unchanged scene 30 times a second is pure heat, so the view drops to
    /// `idleFramesPerSecond` once nothing has happened for `idleDelay`.
    enum FrameRate {
        static let active = 30
        static let idle = 8
        /// Grace period before sleeping, long enough to cover the gap between
        /// one-second simulation ticks without flapping.
        static let idleDelay: TimeInterval = 1.4
    }

    /// Identity of the last semantic-zoom pass. City label and badge visibility
    /// is recomputed only when one of these actually changes; the zoom step is
    /// quantized so a pinch reads as continuous while a still camera does no work.
    struct SemanticZoomKey: Equatable {
        let zoomStep: Int
        let selected: CityID?
        let hq: CityID?
        let highlightsStarters: Bool
    }

    var lastSemanticZoomKey: SemanticZoomKey?

    var lastActivityAt: TimeInterval = 0
    var isIdle = false

    var hqCityID: CityID?
    var selectedCityID: CityID?
    var selectedVehicleID: VehicleID?
    var highlightsStarterCities = false
    var cameraFocus: MapCameraFocus = .world
    var accentColor = UIColor.systemBlue
    var fitScale: CGFloat = 1
    var hasFittedCamera = false
    var userMovedCamera = false

    let worldBounds: CGRect
    let cameraBounds: CGRect
    let majorCityIDs: Set<CityID>
    let regionalCityIDs: Set<CityID>

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

    var isAnimating: Bool {
        if cameraNode.hasActions() { return true }
        return vehicleNodes.values.contains { $0.hasActions() }
    }

    /// The HQ/starter halo pulse is a `repeatForever` action, so on its own it
    /// would keep the scene permanently busy. It sleeps with the map.
    func setDecorativeAnimationsPaused(_ paused: Bool) {
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
}
