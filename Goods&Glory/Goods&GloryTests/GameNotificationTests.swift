//
//  GameNotificationTests.swift
//  Goods&GloryTests
//
//  Map-focus targets for tappable route notifications.
//

import Foundation
import Testing
@testable import Goods_Glory

struct GameNotificationTests {
    @Test func pickupFocusesOriginCity() {
        let origin = CityID("us_chicago")
        let destination = CityID("us_las_vegas")
        let event = LogEvent.jobPickedUp(
            jobID: JobID(rawValue: 1),
            origin: origin,
            destination: destination
        )
        #expect(GameNotification.mapFocusCity(for: event) == origin)
    }

    @Test func routeDeliveryFocusesDestinationCity() {
        let destination = CityID("us_dallas")
        let event = LogEvent.routeShipmentDelivered(
            routeID: RouteID(rawValue: 1),
            jobID: JobID(rawValue: 1),
            destination: destination,
            revenue: 800
        )
        #expect(GameNotification.mapFocusCity(for: event) == destination)
    }

    @Test func makeAttachesMapFocusForPickup() throws {
        let catalog = try GameCatalog.load(from: .main)
        let origin = CityID("us_chicago")
        let destination = CityID("us_las_vegas")
        let pickup = try #require(GameNotification.make(
            from: LogEntry(
                id: 1,
                at: .start,
                event: .jobPickedUp(
                    jobID: JobID(rawValue: 1),
                    origin: origin,
                    destination: destination
                )
            ),
            catalog: catalog
        ))
        #expect(pickup.mapFocusCityID == origin)
    }
}
