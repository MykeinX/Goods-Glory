//
//  GameMapScene+Terrain.swift
//  Goods&Glory
//
//  One-time scene construction: batched land and water geometry plus the
//  city nodes. Built once, then only restyled.
//

import QuartzCore
import SpriteKit
import UIKit

extension GameMapScene {
    // MARK: - Static scene

    func buildScene() {
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

        // White casing beneath the coloured line: a crisp cut-out edge that
        // keeps routes legible over both the grey land and the blue sea, the
        // way a metro line stays readable across a printed map.
        activeRouteHaloNode.strokeColor = MapPalette.routeCasing
        activeRouteHaloNode.lineCap = .round
        activeRouteHaloNode.lineJoin = .round
        activeRouteHaloNode.lineWidth = StrokeWidth.activeRouteHalo
        activeRouteHaloNode.zPosition = 1
        routeLayer.addChild(activeRouteHaloNode)

        activeRouteNode.strokeColor = accentColor
        activeRouteNode.lineCap = .round
        activeRouteNode.lineJoin = .round
        activeRouteNode.lineWidth = StrokeWidth.activeRoute
        activeRouteNode.zPosition = 2
        routeLayer.addChild(activeRouteNode)

        plannedRouteNode.strokeColor = accentColor.withAlphaComponent(0.78)
        plannedRouteNode.lineCap = .round
        plannedRouteNode.lineJoin = .round
        plannedRouteNode.lineWidth = StrokeWidth.plannedRoute
        plannedRouteNode.glowWidth = 1
        plannedRouteLayer.addChild(plannedRouteNode)
    }

    /// Projected, simplified world silhouettes.
    ///
    /// The projection is a pure function of immutable catalog data and the
    /// simplification tolerances are constants, so every map surface in the app
    /// builds byte-identical paths. Building them once and handing out the same
    /// `CGPath` objects removes thousands of coordinate projections and a full
    /// Douglas–Peucker pass from every scene after the first — which is what
    /// opening the city detail or route builder screen used to pay for.
    @MainActor
    enum TerrainPaths {
        static let cache = Cache()

        /// The silhouette ships as authored Mini Metro art (import_board_art.py)
        /// with octilinear coasts already baked in. This is the single
        /// "iOS box-radius" knob: how far a coast corner is rounded, in world
        /// units (≈ km). Large enough to read as premium iOS softness without
        /// melting continents into blobs.
        static let coastCornerRadiusKm: CGFloat = 200

        final class Cache {
            var built: CGPath?

            func land(
                board: MapBoardSilhouette,
                projection: MapProjection
            ) -> CGPath {
                if let built { return built }
                let value = Self.build(board: board, projection: projection)
                built = value
                return value
            }

            private static func build(
                board: MapBoardSilhouette,
                projection: MapProjection
            ) -> CGPath {
                let landPath = CGMutablePath()
                for landMass in board.landMasses where landMass.points.count >= 3 {
                    var projected = landMass.points.map(projection.point(for:))
                    if let first = projected.first, let last = projected.last,
                       hypot(first.x - last.x, first.y - last.y) < 0.01 {
                        projected.removeLast()
                    }
                    guard projected.count >= 3 else { continue }
                    // Native quadratic curves stay smooth under close zoom and
                    // keep the cached path smaller than sampled polylines.
                    landPath.addRoundedClosedPolyline(
                        projected,
                        cornerRadius: coastCornerRadiusKm,
                        maximumCornerFraction: 0.18
                    )
                }
                return landPath
            }
        }
    }

    enum TerrainShadowStyle {
        // A filled duplicate is both cheaper and more reliable than stroked or
        // shader-blurred coastlines: those produce wedges at tight corners.
        static let alpha: CGFloat = 0.24
        static let screenOffsetY: CGFloat = -5
    }

    func addGeography() {
        let landPath = TerrainPaths.cache.land(
            board: .bundled,
            projection: projection
        )

        // One flat sea quad, exactly the reference tone. It is oversized to
        // cover every legal camera position and portrait overscan.
        let water = SKSpriteNode(
            color: MapPalette.water,
            size: CGSize(
                width: cameraBounds.width * 4,
                height: cameraBounds.height * 4
            )
        )
        water.position = CGPoint(x: cameraBounds.midX, y: cameraBounds.midY)
        water.zPosition = 0
        terrainLayer.addChild(water)

        // A slightly lowered copy of the filled silhouette supplies the blue
        // lift from the reference. The land covers its interior, leaving one
        // clean edge without stroke joins, glow shaders or effect textures.
        landShadowNode.path = landPath
        landShadowNode.fillColor = MapPalette.landShadow.withAlphaComponent(
            TerrainShadowStyle.alpha
        )
        landShadowNode.strokeColor = .clear
        landShadowNode.lineWidth = 0
        landShadowNode.glowWidth = 0
        landShadowNode.isAntialiased = true
        landShadowNode.position = CGPoint(x: 0, y: TerrainShadowStyle.screenOffsetY)
        landShadowNode.zPosition = 0.5
        terrainLayer.addChild(landShadowNode)

        landNode.path = landPath
        landNode.fillColor = MapPalette.land
        landNode.strokeColor = MapPalette.coastline
        landNode.lineWidth = StrokeWidth.landCoast
        landNode.lineJoin = .round
        landNode.zPosition = 1
        terrainLayer.addChild(landNode)
    }

    func addCities() {
        for city in catalog.cities {
            let node = MapCityNode(city: city)
            node.position = projection.point(for: city)
            cityLayer.addChild(node)
            cityNodes[city.id] = node
        }
        updateCityStyles()
    }

}
