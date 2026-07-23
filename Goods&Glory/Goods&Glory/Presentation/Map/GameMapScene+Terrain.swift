//
//  GameMapScene+Terrain.swift
//  Goods&Glory
//
//  One-time scene construction: batched land, water and border geometry
//  plus the city nodes. Built once, then only restyled.
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

        activeRouteHaloNode.strokeColor = accentColor.withAlphaComponent(0.18)
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

        struct Built {
            let land: CGPath
            let boundaries: CGPath?
        }

        final class Cache {
            var built: Built?

            func paths(
                boundaryAtlas: MapBoundaryAtlas,
                board: MapBoardSilhouette,
                projection: MapProjection
            ) -> Built {
                if let built { return built }
                let value = Self.build(
                    boundaryAtlas: boundaryAtlas,
                    board: board,
                    projection: projection
                )
                built = value
                return value
            }

            private static func build(
                boundaryAtlas: MapBoundaryAtlas,
                board: MapBoardSilhouette,
                projection: MapProjection
            ) -> Built {
                let landPath = CGMutablePath()
                for landMass in board.landMasses where landMass.points.count >= 3 {
                    let points = landMass.points.map(projection.point(for:))
                    guard points.count >= 3 else { continue }
                    landPath.addRoundedClosedPolyline(points)
                }

                let boundaryPath = CGMutablePath()
                var boundaryCount = 0
                for line in boundaryAtlas.lines where line.count >= 2 {
                    let points = line.map(projection.point(for:))
                    guard points.count >= 2 else { continue }
                    boundaryPath.addOpenPolyline(points)
                    boundaryCount += 1
                }

                return Built(
                    land: landPath,
                    boundaries: boundaryCount > 0 ? boundaryPath : nil
                )
            }
        }
    }

    func addGeography() {
        let paths = TerrainPaths.cache.paths(
            boundaryAtlas: boundaryAtlas,
            board: .bundled,
            projection: projection
        )

        // One oversized quad covers every legal camera position and portrait
        // overscan; its edges must never appear as horizontal color seams.
        let waterGradient = SKSpriteNode(
            color: .white,
            size: CGSize(
                width: cameraBounds.width * 4,
                height: cameraBounds.height * 4
            )
        )
        waterGradient.position = CGPoint(x: cameraBounds.midX, y: cameraBounds.midY)
        waterGradient.shader = SKShader(source: """
            void main() {
                vec2 delta = v_tex_coord - vec2(0.5);
                float glow = 1.0 - smoothstep(0.05, 0.76, length(delta));
                vec3 edge = vec3(0.25, 0.49, 0.86);
                vec3 center = vec3(0.43, 0.66, 0.96);
                gl_FragColor = vec4(mix(edge, center, glow), 1.0);
            }
            """)
        waterGradient.zPosition = 0
        terrainLayer.addChild(waterGradient)

        landNode.path = paths.land
        landNode.fillColor = MapPalette.land
        landNode.strokeColor = MapPalette.coastline
        landNode.lineWidth = StrokeWidth.landCoast
        landNode.lineJoin = .round
        landNode.zPosition = 1
        terrainLayer.addChild(landNode)

        // One quiet batched border stroke keeps countries readable without
        // turning the game board into a navigation atlas.
        if let boundaryPath = paths.boundaries {
            boundaryNode.path = boundaryPath
            boundaryNode.fillColor = .clear
            boundaryNode.strokeColor = MapPalette.boundary
            boundaryNode.lineWidth = StrokeWidth.boundary
            boundaryNode.lineCap = .round
            boundaryNode.lineJoin = .round
            boundaryNode.isAntialiased = true
            boundaryNode.zPosition = 2
            terrainLayer.addChild(boundaryNode)
        }

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
