//
//  MapCorridorContractTests.swift
//  Goods&GloryTests
//
//  Contracts for the baked Mini Metro-style road geometry. The land mask lives
//  in generate_trade_network.py, which refuses to emit a road across water;
//  these tests guard what that script must never stop producing.
//

import CoreGraphics
import Foundation
import Testing
@testable import Goods_Glory

struct MapCorridorContractTests {
    /// Lattice pitch in projected km, mirroring scripts/map_grid.py.
    private let latticeStepKm: CGFloat = 45

    @MainActor @Test func everyRoadHasGeometryJoinedToItsRoadNodes() throws {
        let catalog = try GameCatalog.load(from: .main)
        let geometry = MapRoadGeometry.bundled
        let polylines = Dictionary(
            geometry.roads.map { ($0.id, $0.points) },
            uniquingKeysWith: { first, _ in first }
        )
        #expect(polylines.count == geometry.roads.count, "duplicate road geometry")
        #expect(polylines.count == catalog.roads.count)

        for road in catalog.roads {
            let points = try #require(polylines[road.id], "\(road.id) has no geometry")
            #expect(points.count >= 2)
            let from = try #require(catalog.networkNode(road.from))
            let to = try #require(catalog.networkNode(road.to))
            // A gap here shows up as a city pin floating off its own road.
            #expect(points.first == from.coordinate)
            #expect(points.last == to.coordinate)
        }
    }

    @MainActor @Test func everyBundledRoadIsOctilinearAndOnTheSharedLattice() throws {
        let catalog = try GameCatalog.load(from: .main)
        let projection = MapProjection()
        let corridors = MapCorridorCache()

        for road in catalog.roads {
            let points = try #require(
                corridors.points(for: road.id, catalog: catalog, projection: projection)
            )
            #expect(points.count >= 2)
            #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            assertOnLattice(points, label: road.id.rawValue)
        }
    }

    @MainActor @Test func cityCorridorsStayOctilinearEndToEnd() throws {
        let catalog = try GameCatalog.load(from: .main)
        let projection = MapProjection()
        let corridors = MapCorridorCache()

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
                assertOnLattice(corridor.points, label: "\(origin.id)->\(destinationID)")
            }
        }
    }

    /// Being octilinear is not enough to read as a line: a two-cell diagonal
    /// between two long straights is a wobble, not a bend. Short runs are only
    /// allowed where a corridor genuinely starts or ends.
    @MainActor @Test func corridorsBendInReadableRunsRatherThanWobbling() throws {
        let catalog = try GameCatalog.load(from: .main)
        let projection = MapProjection()
        let corridors = MapCorridorCache()
        let shortestInteriorRun = latticeStepKm * 3

        for origin in catalog.cities {
            for destinationID in catalog.reachableCities(from: origin.id) {
                let points = corridors.corridor(
                    from: origin.id,
                    to: destinationID,
                    catalog: catalog,
                    projection: projection
                ).points
                guard points.count > 3 else { continue }

                let interior = zip(points, points.dropFirst()).dropFirst().dropLast()
                for (start, end) in interior {
                    let length = hypot(end.x - start.x, end.y - start.y)
                    #expect(
                        length >= shortestInteriorRun - 1,
                        "\(origin.id)->\(destinationID) wobbles: \(Int(length)) km run"
                    )
                }
            }
        }
    }

    /// Every run is an exact horizontal, vertical or 45° multiple of the shared
    /// lattice pitch, which is what keeps parallel trunks parallel.
    private func assertOnLattice(_ points: [CGPoint], label: String) {
        for (start, end) in zip(points, points.dropFirst()) {
            let columns = (end.x - start.x) / latticeStepKm
            let rows = (end.y - start.y) / latticeStepKm
            #expect(abs(columns - columns.rounded()) < 0.02, "\(label) is off-lattice")
            #expect(abs(rows - rows.rounded()) < 0.02, "\(label) is off-lattice")
            let steps = (columns: abs(columns.rounded()), rows: abs(rows.rounded()))
            #expect(steps.columns > 0 || steps.rows > 0, "\(label) has a null segment")
            #expect(
                steps.columns == 0 || steps.rows == 0 || steps.columns == steps.rows,
                "\(label) has an off-angle segment"
            )
        }
    }
}
