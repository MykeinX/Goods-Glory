//
//  CatalogBudgetTests.swift
//  Goods&GloryTests
//
//  Size limits on bundled content.
//
//  Content is the easiest thing in the project to grow by accident. Twice
//  during the world build it doubled without anyone deciding to: the map
//  geography went to 24,718 vertices while chasing an unrelated detail bug, and
//  the road graph to 1,403 nodes while chasing a coastline crossing. Neither
//  showed up as a failure — the game still ran, the tests still passed, and it
//  only surfaced when a human looked at a diff.
//
//  This is a phone game. Every kilobyte here is parsed at launch and held for
//  the session. These budgets are not aspirations; they are roughly twice the
//  current numbers, so ordinary content work never touches them and a silent
//  doubling always does.
//
//  Road budgets intentionally leave room for the planned global expansion;
//  the lower bound protects the deliberately small foundation catalog.
//

import Foundation
import Testing
@testable import Goods_Glory

@Suite("Catalog budgets")
struct CatalogBudgetTests {
    /// Every drawn vertex of the board silhouette.
    static let geographyVertexBudget = 4_000
    /// Road graph size. One node per city; edges are the sparse authored
    /// backbone. Density belongs in city count, not invisible steering nodes.
    static let roadNodeBudget = 1_500
    static let roadEdgeBudget = 2_000
    /// Guards the other direction too: a catalog that lost its content should
    /// fail loudly rather than quietly shipping an empty world.
    static let minimumCities = 19

    @MainActor
    @Test("Bundled map geography stays inside its vertex budget")
    func geographyVertexCount() throws {
        let board = try MapBoardSilhouette.load(from: .main)
        let vertices = board.landMasses.reduce(0) { $0 + $1.points.count }

        #expect(vertices > 500, "geography looks empty at \(vertices) vertices")
        #expect(
            vertices <= Self.geographyVertexBudget,
            "map geography is \(vertices) vertices, over the \(Self.geographyVertexBudget) budget — coarsen it or raise the budget deliberately"
        )
    }

    @Test("Bundled road graph stays inside its budget")
    func roadGraphSize() throws {
        let catalog = try GameCatalog.load(from: .main)

        #expect(catalog.cities.count >= Self.minimumCities)
        #expect(
            catalog.networkNodes.count <= Self.roadNodeBudget,
            "road graph is \(catalog.networkNodes.count) nodes, over the \(Self.roadNodeBudget) budget"
        )
        #expect(
            catalog.roads.count <= Self.roadEdgeBudget,
            "road graph is \(catalog.roads.count) edges, over the \(Self.roadEdgeBudget) budget"
        )
    }

    /// Every road node is a city. Extra nodes would mean the old junction
    /// system leaked back in.
    @Test("Road nodes match cities one-to-one")
    func roadNodesMatchCities() throws {
        let catalog = try GameCatalog.load(from: .main)
        #expect(catalog.networkNodes.count == catalog.cities.count)
        #expect(catalog.networkNodes.allSatisfy { $0.kind == .city && $0.cityID != nil })
    }
}
