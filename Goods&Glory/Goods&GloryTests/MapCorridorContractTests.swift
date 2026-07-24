//
//  MapCorridorContractTests.swift
//  Goods&GloryTests
//
//  Contracts for shared Mini Metro-style road geometry.
//

import CoreGraphics
import Foundation
import Testing
@testable import Goods_Glory

struct MapCorridorContractTests {
    @MainActor @Test func schematicLegUsesOnlyMetroGuideAngles() {
        let points = MapCorridorCache.octilinearLeg(
            from: .zero,
            to: CGPoint(x: 120, y: 70)
        )

        #expect(points.count == 3)
        for (start, end) in zip(points, points.dropFirst()) {
            let angle = atan2(end.y - start.y, end.x - start.x)
            let eighthTurns = angle / (.pi / 4)
            #expect(abs(eighthTurns - eighthTurns.rounded()) < 0.0001)
        }
    }

    @MainActor @Test func everyBundledRoadBuildsSharedContinuousMapGeometry() throws {
        let catalog = try GameCatalog.load(from: .main)
        let projection = MapProjection()
        let corridors = MapCorridorCache()

        for road in catalog.roads {
            let points = try #require(
                corridors.points(
                    for: road.id,
                    catalog: catalog,
                    projection: projection
                )
            )
            #expect(points.count >= 2)
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            #expect(
                zip(points, points.dropFirst()).allSatisfy {
                    hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) > 0.01
                }
            )
        }

        for origin in catalog.cities {
            for destinationID in catalog.reachableCities(from: origin.id) {
                let destination = try #require(catalog.city(destinationID))
                let corridor = corridors.corridor(
                    from: origin.id,
                    to: destinationID,
                    catalog: catalog,
                    projection: projection
                )
                let first = try #require(corridor.points.first)
                let last = try #require(corridor.points.last)
                let expectedFirst = projection.point(for: origin)
                let expectedLast = projection.point(for: destination)

                #expect(hypot(first.x - expectedFirst.x, first.y - expectedFirst.y) < 1)
                #expect(hypot(last.x - expectedLast.x, last.y - expectedLast.y) < 1)
            }
        }
    }
}
