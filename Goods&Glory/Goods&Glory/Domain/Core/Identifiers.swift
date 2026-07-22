//
//  Identifiers.swift
//  Goods&Glory
//
//  Typed identifiers for catalog (static content) and runtime (live) entities.
//  Catalog IDs are stable lowercase_snake_case strings defined in JSON data.
//  Runtime IDs are deterministic sequential integers issued by GameState.
//

import Foundation

/// A type-safe wrapper around a stable string identifier from the content catalog.
/// The phantom `Tag` prevents mixing e.g. a city ID with a vehicle type ID.
struct CatalogID<Tag>: RawRepresentable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CatalogID: Codable {
    init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension CatalogID: CustomStringConvertible {
    var description: String { rawValue }
}

enum CityTag {}
enum RoadTag {}
enum RoadNodeTag {}
enum VehicleTypeTag {}
enum ProductTag {}
enum FirmTag {}
enum LaneTag {}

typealias CityID = CatalogID<CityTag>
typealias RoadID = CatalogID<RoadTag>
typealias RoadNodeID = CatalogID<RoadNodeTag>
typealias VehicleTypeID = CatalogID<VehicleTypeTag>
typealias ProductID = CatalogID<ProductTag>
/// Derived catalog entity: one trading firm per (city, product, role).
typealias FirmID = CatalogID<FirmTag>
/// Derived catalog entity: one persistent freight lane per
/// (origin city, product, destination city). See `GameCatalog.deriveLanes`.
typealias LaneID = CatalogID<LaneTag>

/// A type-safe wrapper around a deterministic sequential integer for live entities.
/// Issued via `GameState.issueID()` so identical command sequences yield identical IDs.
struct RuntimeID<Tag>: RawRepresentable, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

extension RuntimeID: Codable {
    init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension RuntimeID: CustomStringConvertible {
    var description: String { "#\(rawValue)" }
}

enum VehicleTag {}
enum JobTag {}
enum ContractTag {}
enum RouteTag {}
enum FacilityTag {}

typealias VehicleID = RuntimeID<VehicleTag>
typealias JobID = RuntimeID<JobTag>
typealias ContractID = RuntimeID<ContractTag>
typealias RouteID = RuntimeID<RouteTag>
typealias FacilityID = RuntimeID<FacilityTag>
