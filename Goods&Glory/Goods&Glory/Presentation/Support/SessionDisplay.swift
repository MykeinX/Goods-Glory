//
//  SessionDisplay.swift
//  Goods&Glory
//
//  Presentation-side lookups every screen needs: the company accent colour and
//  the display names behind catalog IDs.
//
//  These lived as identical private helpers in a dozen views — thirteen copies
//  of the accent colour alone. One definition means a change to how the company
//  colour falls back, or how an unknown city renders, happens once.
//
//  It extends `GameSession` from the presentation layer rather than living in
//  the Application layer, so the domain keeps knowing nothing about SwiftUI.
//

import SwiftUI

extension GameSession {
    /// The company's corporate colour, or the brand default before founding.
    var accentColor: Color {
        Color(hex: state?.config.identity.colorHex ?? "#FFB037")
    }

    func cityName(_ id: CityID) -> String {
        catalog.city(id)?.name ?? id.rawValue
    }

    func productName(_ id: ProductID) -> String {
        catalog.product(id)?.name ?? id.rawValue
    }

    func productSymbol(_ id: ProductID) -> String {
        catalog.product(id)?.symbol ?? "shippingbox.fill"
    }

    func firmName(_ id: FirmID?) -> String? {
        id.flatMap { catalog.firm($0)?.name }
    }

    /// Fleet code such as `BOX-04`.
    func vehicleCode(_ vehicle: Vehicle) -> String {
        let typeName = catalog.vehicleType(vehicle.typeID)?.name ?? "VEH"
        return Format.vehicleCode(typeName: typeName, id: vehicle.id)
    }

    /// "Acme Works → Nova Distribution" when both addresses are known.
    func addressLine(from originFirmID: FirmID?, to destinationFirmID: FirmID?) -> String? {
        guard let origin = firmName(originFirmID),
              let destination = firmName(destinationFirmID) else { return nil }
        return "\(origin) → \(destination)"
    }
}
