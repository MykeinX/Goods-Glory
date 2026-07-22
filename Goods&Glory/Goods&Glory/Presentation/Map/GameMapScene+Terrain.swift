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
    enum TerrainPaths {
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
            var built: Built?

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
                // The bundled data holds a few 4-point lakes and exact duplicate
                // rings; at strategic zoom they read as stray angular shapes
                // rather than water, so only well-formed, unique lakes are drawn.
                var seenWaterSignatures = Set<String>()
                for body in geography.waterBodies where body.points.count >= 5 {
                    let signature = body.points
                        .map { "\($0.latitude),\($0.longitude)" }
                        .joined(separator: ";")
                    guard seenWaterSignatures.insert(signature).inserted else { continue }
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

    func addGeography() {
        let paths = TerrainPaths.cache.paths(geography: geography, projection: projection)

        let land = SKShapeNode(path: paths.land)
        land.fillColor = MapPalette.land
        land.strokeColor = MapPalette.coastline
        land.lineWidth = StrokeWidth.landCoast
        land.lineJoin = .round
        land.zPosition = 1
        terrainLayer.addChild(land)

        // Country borders: static dual stroke (soft halo + main). Same path
        // data as before — only weight and ink change, no geometry rebuild.
        if let boundaryPath = paths.boundaries {
            let halo = SKShapeNode(path: boundaryPath)
            halo.fillColor = .clear
            halo.strokeColor = MapPalette.boundaryHalo
            halo.lineWidth = StrokeWidth.boundaryHalo
            halo.lineCap = .round
            halo.lineJoin = .round
            halo.isAntialiased = true
            halo.zPosition = 2
            terrainLayer.addChild(halo)

            let borders = SKShapeNode(path: boundaryPath)
            borders.fillColor = .clear
            borders.strokeColor = MapPalette.boundary
            borders.lineWidth = StrokeWidth.boundary
            borders.lineCap = .round
            borders.lineJoin = .round
            borders.isAntialiased = true
            borders.zPosition = 2.1
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
