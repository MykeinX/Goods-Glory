//
//  ActiveWorkRows.swift
//  Goods&Glory
//
//  A plain vehicle line: name, and where it is or that it is working.
//
//  The per-job and per-route-run cards that used to live here were removed with
//  the operations list they fed — that view is a per-city network now. This row
//  predates them and has no call site either; left in place deliberately rather
//  than deleted as part of an unrelated change.
//

import SwiftUI

struct VehicleRow: View {
    @Environment(GameSession.self) private var session
    let vehicle: Vehicle

    var body: some View {
        HStack {
            if let vehicleType = session.catalog.vehicleType(vehicle.typeID) {
                Label(String(localized: String.LocalizationValue(vehicleType.name)), systemImage: vehicleType.symbol)
                    .font(.gg(13.5, .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if vehicle.isAvailable {
                Text(session.catalog.city(vehicle.cityID)?.name ?? "")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text("On the job")
                    .font(.gg(12, .bold))
                    .foregroundStyle(Theme.mint)
            }
        }
    }
}
