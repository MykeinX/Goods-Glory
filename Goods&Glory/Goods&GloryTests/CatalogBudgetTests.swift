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
//  When a budget legitimately needs to rise, raise it in the same commit as the
//  content and say why. The point is that it becomes a decision.
//

import Foundation
import Testing
@testable import Goods_Glory

@Suite("Catalog budgets")
struct CatalogBudgetTests {
    /// Every drawn vertex of the board silhouette.
    static let geographyVertexBudget = 4_000
    /// Road graph size. Junctions exist to keep a leg on land, nothing more —
    /// density belongs where the coast forces a bend, not spread evenly.
    static let roadNodeBudget = 1_500
    static let roadEdgeBudget = 2_000
    /// Guards the other direction too: a catalog that lost its content should
    /// fail loudly rather than quietly shipping an empty world.
    static let minimumCities = 60

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

    /// Junction count should track the coastline's demands, not the city count.
    /// A fixed-interval resampling pass — the mistake that tripled this graph —
    /// shows up here immediately.
    @Test("Junctions stay proportionate to cities")
    func junctionDensity() throws {
        let catalog = try GameCatalog.load(from: .main)
        let junctions = catalog.networkNodes.count - catalog.cities.count
        let perCity = Double(junctions) / Double(max(catalog.cities.count, 1))

        #expect(
            perCity < 20,
            "\(junctions) junctions for \(catalog.cities.count) cities (\(perCity) each) — that is uniform resampling, not terrain-driven density"
        )
    }
}
