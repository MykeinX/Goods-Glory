//
//  GameCatalog+Validation.swift
//  Goods&Glory
//
//  Cross-reference and physical sanity checks run at load.
//

import Foundation

extension GameCatalog {
    static let maximumCityRoadNodeDistanceKm = 25.0
    /// Gameplay guardrails wide enough for future global normalization while
    /// still catching a missing x1000 fixed-point scale in catalog data.
    static let plausibleCostIndexRange: ClosedRange<UInt16> = 250...4_000
    static let plausibleTrafficDelayIndexRange: ClosedRange<UInt16> = 1_000...5_000

    static func validateNetworkNodes(
        _ nodes: [NetworkNodeDefinition],
        citiesByID: [CityID: CityDefinition],
        networkNodesByID: [RoadNodeID: NetworkNodeDefinition]
    ) throws {
        var linkedCityIDs: Set<CityID> = []
        for node in nodes {
            try validateCoordinate(node.coordinate, label: "road node \(node.id)")
            switch (node.kind, node.cityID) {
            case (.city, .some(let cityID)):
                guard let city = citiesByID[cityID], city.roadNodeID == node.id else {
                    throw CatalogError.validationFailure("road node \(node.id) has invalid city link")
                }
                guard linkedCityIDs.insert(cityID).inserted else {
                    throw CatalogError.validationFailure("city \(cityID) is linked to multiple road nodes")
                }
            default:
                throw CatalogError.validationFailure("road node \(node.id) has invalid kind or city link")
            }
        }

        for city in citiesByID.values {
            try validateCoordinate(city.coordinate, label: "city \(city.id)")
            guard let node = networkNodesByID[city.roadNodeID], node.cityID == city.id else {
                throw CatalogError.validationFailure("city \(city.id) references invalid road node")
            }
            guard geographicDistanceKm(city.coordinate, node.coordinate) <= maximumCityRoadNodeDistanceKm else {
                throw CatalogError.validationFailure("city \(city.id) road node is too far from its coordinate")
            }
        }
    }

    static func validateCoordinate(_ coordinate: GeoCoordinate, label: String) throws {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              (-90...90).contains(coordinate.latitude),
              (-180...180).contains(coordinate.longitude) else {
            throw CatalogError.validationFailure("\(label) has invalid coordinate")
        }
    }

    static func geographicDistanceKm(_ lhs: GeoCoordinate, _ rhs: GeoCoordinate) -> Double {
        let degreesToRadians = Double.pi / 180
        let latitudeDelta = (rhs.latitude - lhs.latitude) * degreesToRadians
        let longitudeDelta = (rhs.longitude - lhs.longitude) * degreesToRadians
        let lhsLatitude = lhs.latitude * degreesToRadians
        let rhsLatitude = rhs.latitude * degreesToRadians
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(lhsLatitude) * cos(rhsLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 6_371 * 2 * asin(sqrt(max(0, min(1, a))))
    }

    func validate() throws {
        guard !cities.isEmpty else { throw CatalogError.validationFailure("no cities defined") }
        guard !starterCities.isEmpty else { throw CatalogError.validationFailure("no starter city defined") }
        guard !vehicleTypes.isEmpty else { throw CatalogError.validationFailure("no vehicle types defined") }
        guard !products.isEmpty else { throw CatalogError.validationFailure("no products defined") }

        for city in cities {
            guard !city.name.isEmpty, !city.country.isEmpty, city.population > 0,
                  Self.plausibleCostIndexRange.contains(city.costIndex),
                  Self.plausibleTrafficDelayIndexRange.contains(city.trafficDelayIndex) else {
                throw CatalogError.validationFailure("city \(city.id) has invalid baseline data")
            }
        }

        for vehicleType in vehicleTypes {
            guard vehicleType.capacity.massKg > 0, vehicleType.capacity.volumeM3 > 0,
                  vehicleType.speedKmh > 0, vehicleType.purchasePrice > 0,
                  vehicleType.fixedCostPerDay >= 0,
                  vehicleType.costPerKm >= 0, vehicleType.driverCostPerHour >= 0 else {
                throw CatalogError.validationFailure("vehicle type \(vehicleType.id) has non-positive physical values")
            }
        }
        for product in products {
            let massStepKg = ProductDefinition.shipmentMassStepKg
            let minimumMassUnits = product.minimumShipmentMassKg / massStepKg
                + (product.minimumShipmentMassKg % massStepKg == 0 ? 0 : 1)
            let maximumMassUnits = product.maximumShipmentMassKg
                / massStepKg
            guard Self.isStableCatalogID(product.id.rawValue),
                  !product.name.isEmpty, !product.symbol.isEmpty,
                  product.minimumShipmentMassKg > 0,
                  product.maximumShipmentMassKg >= product.minimumShipmentMassKg,
                  minimumMassUnits <= maximumMassUnits,
                  product.densityM3PerTon.isFinite, product.densityM3PerTon > 0 else {
                throw CatalogError.validationFailure("product \(product.id) has invalid ID or physical values")
            }
        }
        try validateCityMarkets()
        guard economy.startingCash > 0,
              economy.loadingMinutes >= 0, economy.unloadingMinutes >= 0,
              (0...1).contains(economy.fillFloor) else {
            throw CatalogError.validationFailure("economy config has invalid values")
        }
        guard economy.lanes.cityOutboundKgPerDayPer100k > 0,
              economy.lanes.minimumRatePerDayKg > 0,
              (0..<100).contains(economy.lanes.weeklySwingPercent),
              economy.lanes.distanceHalfWeightKm > 0,
              economy.lanes.parcelPatienceMinutes >= LaneConfig.tickMinutes else {
            throw CatalogError.validationFailure("lane config has invalid values")
        }
        for lane in lanes {
            guard lane.originCityID != lane.destinationCityID,
                  lane.baseRatePerDayKg >= 1,
                  firmsByID[lane.originFirmID]?.role == .supplier,
                  firmsByID[lane.destinationFirmID]?.role == .receiver,
                  cityDistances[lane.originCityID]?[lane.destinationCityID] != nil else {
                throw CatalogError.validationFailure("freight lane \(lane.id) is malformed")
            }
        }
        guard let cheapestVehicle = vehicleTypes.map(\.purchasePrice).min() else {
            throw CatalogError.validationFailure("no vehicle type is affordable with starting cash")
        }
        for city in starterCities {
            let foundingCost = CityInsight.foundingCost(for: city)
            guard economy.startingCash > foundingCost else {
                throw CatalogError.validationFailure(
                    "starter city \(city.id) founding cost exceeds starting cash"
                )
            }
            guard economy.startingCash - foundingCost >= cheapestVehicle else {
                throw CatalogError.validationFailure(
                    "starter city \(city.id) leaves too little cash for an entry vehicle"
                )
            }
        }

        // The road graph is one component per landmass, not one component
        // overall: America genuinely has no road to Eurasia, and pretending
        // otherwise would let a truck drive the Atlantic. What must hold is
        // that no node is stranded — every component has to carry at least one
        // city, or a road ends somewhere the simulation can never reach.
        guard !networkNodes.isEmpty else {
            throw CatalogError.validationFailure("no road nodes defined")
        }
        let cityNodeIDs = Set(cities.map(\.roadNodeID))
        var unvisited = Set(networkNodes.map(\.id))
        while let seed = unvisited.first {
            var component: Set<RoadNodeID> = [seed]
            var pending: [RoadNodeID] = [seed]
            while let node = pending.popLast() {
                for edge in adjacency[node] ?? [] where component.insert(edge.neighbor).inserted {
                    pending.append(edge.neighbor)
                }
            }
            guard !component.isDisjoint(with: cityNodeIDs) else {
                throw CatalogError.validationFailure(
                    "road network has a \(component.count)-node island with no city on it"
                )
            }
            unvisited.subtract(component)
        }
    }

    func validateCityMarkets() throws {
        let cityIDs = Set(cities.map(\.id))
        let marketCityIDs = Set(cityMarkets.map(\.cityID))
        guard marketCityIDs == cityIDs else {
            throw CatalogError.validationFailure("city market profiles do not match the city catalog")
        }

        for market in cityMarkets {
            try validateMarketEntries(market.supply, cityID: market.cityID, label: "supply")
            try validateMarketEntries(market.demand, cityID: market.cityID, label: "demand")
        }
    }

    func validateMarketEntries(
        _ entries: [CityProductWeight],
        cityID: CityID,
        label: String
    ) throws {
        guard entries.count <= 20 else {
            throw CatalogError.validationFailure("city \(cityID) has more than 20 \(label) products")
        }

        var seen: Set<ProductID> = []
        for entry in entries {
            guard productsByID[entry.productID] != nil else {
                throw CatalogError.validationFailure(
                    "city \(cityID) \(label) references unknown product \(entry.productID)"
                )
            }
            guard entry.weight > 0, seen.insert(entry.productID).inserted else {
                throw CatalogError.validationFailure(
                    "city \(cityID) \(label) has zero weight or a duplicate product"
                )
            }
        }

        let canonical = entries.sorted {
            $0.weight == $1.weight
                ? $0.productID.rawValue < $1.productID.rawValue
                : $0.weight > $1.weight
        }
        guard entries == canonical else {
            throw CatalogError.validationFailure(
                "city \(cityID) \(label) products are not in canonical order"
            )
        }
    }

    static func isStableCatalogID(_ value: String) -> Bool {
        value.range(
            of: "^[a-z0-9]+(?:_[a-z0-9]+)*$",
            options: .regularExpression
        ) != nil
    }
}
