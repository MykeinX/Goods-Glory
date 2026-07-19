//
//  GameNotificationTests.swift
//  Goods&GloryTests
//
//  Map-focus targets for tappable toasts — extend mapFocusCity(for:) as events grow.
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

    @Test func deliveryFocusesDestinationCity() {
        let destination = CityID("us_las_vegas")
        let event = LogEvent.jobDelivered(
            jobID: JobID(rawValue: 1),
            destination: destination,
            revenue: 1_000,
            cost: 400
        )
        #expect(GameNotification.mapFocusCity(for: event) == destination)
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

    @Test func makeAttachesMapFocusForPickupAndDelivery() throws {
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

        let delivery = try #require(GameNotification.make(
            from: LogEntry(
                id: 2,
                at: .start,
                event: .jobDelivered(
                    jobID: JobID(rawValue: 1),
                    destination: destination,
                    revenue: 1_200,
                    cost: 500
                )
            ),
            catalog: catalog
        ))
        #expect(delivery.mapFocusCityID == destination)
    }

    @Test func contractEndedHasNoMapFocusYet() {
        let event = LogEvent.contractEnded(
            contractID: ContractID(rawValue: 1),
            completed: 3,
            missed: 0
        )
        #expect(GameNotification.mapFocusCity(for: event) == nil)
    }
}
