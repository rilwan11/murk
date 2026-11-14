import XCTest
@testable import Murk

final class FakeCloud: CloudKeyValueStore {
    var values: [String: Data] = [:]
    func data(forKey key: String) -> Data? { values[key] }
    func set(_ data: Data?, forKey key: String) { values[key] = data }
    func removeObject(forKey key: String) { values[key] = nil }
    func synchronize() -> Bool { true }
}

private func settings(_ places: [Place] = [Fixture.la], unit: String = "fahrenheit", skin: String = "graphite") -> SyncedSettings {
    SyncedSettings(places: places, unit: unit, skin: skin, autoSkin: false, minimal: false, headsUp: true, sound: true, rules: NotificationRules())
}

@MainActor
final class CloudSyncTests: XCTestCase {
    private func device(_ cloud: FakeCloud, at time: Double, enabled: Bool = true) -> CloudSync {
        let s = CloudSync(store: cloud, defaults: Fixture.defaults(), now: { Date(timeIntervalSince1970: time) })
        s.enabled = enabled
        return s
    }

    func testNothingLeavesTheDeviceUnlessSyncIsOnAndProIsActive() {
        let cloud = FakeCloud()
        device(cloud, at: 100, enabled: false).push(settings(), isPro: true)
        device(cloud, at: 100).push(settings(), isPro: false)
        XCTAssertTrue(cloud.values.isEmpty)
        device(cloud, at: 100).push(settings(), isPro: true)
        XCTAssertNotNil(cloud.values[CloudSync.key])
    }

    func testAChangeOnOneDeviceReachesTheOtherOnce() {
        let cloud = FakeCloud()
        let phone = device(cloud, at: 100), tablet = device(cloud, at: 50)
        var received: [SyncedSettings] = []
        tablet.onRemote = { received.append($0) }
        let sent = settings([Fixture.la, Fixture.ny], unit: "celsius")
        phone.push(sent, isPro: true)
        tablet.pull(isPro: true)
        tablet.pull(isPro: true)
        XCTAssertEqual(received, [sent])
        // Applying it locally must not bounce the same settings back up as a new change.
        let before = cloud.values[CloudSync.key]
        tablet.push(sent, isPro: true)
        XCTAssertEqual(cloud.values[CloudSync.key], before)
    }

    func testOlderDataInICloudNeverOverwritesNewerLocalChanges() {
        let cloud = FakeCloud()
        let phone = device(cloud, at: 200)
        phone.push(settings(unit: "celsius"), isPro: true)
        device(cloud, at: 150).push(settings(unit: "fahrenheit"), isPro: true)     // a stale device writes late
        var received = 0
        phone.onRemote = { _ in received += 1 }
        phone.pull(isPro: true)
        XCTAssertEqual(received, 0)
    }

    func testTurningOnTakesWhatIsInICloudOrSeedsIt() {
        let cloud = FakeCloud()
        let first = device(cloud, at: 100, enabled: false)
        first.turnOn(current: settings([Fixture.la]), isPro: true)
        XCTAssertNotNil(cloud.values[CloudSync.key], "an empty iCloud is seeded from this device")

        let second = device(cloud, at: 300, enabled: false)
        var received: [SyncedSettings] = []
        second.onRemote = { received.append($0) }
        second.turnOn(current: settings([Fixture.ny]), isPro: true)
        XCTAssertEqual(received.first?.places, [Fixture.la], "existing iCloud data wins over a device that joins later")
    }

    func testResetRemovesTheDataAndTurnsSyncOff() {
        let cloud = FakeCloud()
        let phone = device(cloud, at: 100)
        phone.push(settings(), isPro: true)
        phone.reset()
        XCTAssertNil(cloud.values[CloudSync.key])
        XCTAssertFalse(phone.enabled)
    }

    func testOnlyCitiesAndPreferencesAreSynced() throws {
        let cloud = FakeCloud()
        device(cloud, at: 100).push(settings(), isPro: true)
        let text = String(decoding: try XCTUnwrap(cloud.values[CloudSync.key]), as: UTF8.self)
        for forbidden in ["selectedID", "currentPlace", "history", "isCurrentLocation\":true"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
    }

    func testAppliedSettingsRespectTheFreeTierAndKeepNotificationSwitchesLocal() async {
        let state = makeState(places: [Fixture.la])
        var incoming = settings([Fixture.la, Fixture.ny], unit: "celsius", skin: "aurora")
        incoming.rules.rain = true
        incoming.rules.rainChance = 40
        state.apply(incoming)
        XCTAssertEqual(state.places, [Fixture.la, Fixture.ny])
        XCTAssertEqual(state.unit, .celsius)
        XCTAssertEqual(state.skin, .graphite, "a Pro skin from another device is not applied without Pro")
        XCTAssertFalse(state.rules.rain, "each device keeps its own notification switches")
        XCTAssertEqual(state.rules.rainChance, 40, "thresholds do sync")
        XCTAssertEqual(state.syncedSettings.places, [Fixture.la, Fixture.ny])
    }
}

final class WidgetChoiceTests: XCTestCase {
    private let places = [SharedPlace(Fixture.la), SharedPlace(Fixture.ny)]

    func testFreeWidgetsFollowTheAppInTheLiveSky() {
        let c = WidgetChoice.resolve(placeID: Fixture.ny.id, look: .midnight, isPro: false, places: places)
        XCTAssertNil(c.place)
        XCTAssertEqual(c.look, .sky)
    }

    func testProWidgetsUseTheChosenCityAndStyle() {
        let c = WidgetChoice.resolve(placeID: Fixture.ny.id, look: .midnight, isPro: true, places: places)
        XCTAssertEqual(c.place?.name, "New York")
        XCTAssertEqual(c.look, .midnight)
    }

    func testADeletedCityFallsBackToFollowingTheApp() {
        let c = WidgetChoice.resolve(placeID: "Gone|1.000|2.000", look: .skin, isPro: true, places: places)
        XCTAssertNil(c.place)
        XCTAssertEqual(c.look, .skin)
        XCTAssertNil(WidgetChoice.resolve(placeID: nil, look: .sky, isPro: true, places: places).place)
    }

    func testOnlyTheLiveSkyIsFree() {
        XCTAssertEqual(WidgetLook.allCases.filter { !$0.isPremium }, [.sky])
    }

    func testSharedPlacesAreRoundedAndPerCityFilesRevealNothing() {
        let shared = SharedPlace(Fixture.la)
        XCTAssertEqual(shared.id, Fixture.la.id)
        XCTAssertEqual(shared.latitude, 34.05, accuracy: 0.0001)
        XCTAssertEqual(shared.longitude, -118.24, accuracy: 0.0001)
        let a = WidgetSnapshot.fileName(placeID: Fixture.la.id), b = WidgetSnapshot.fileName(placeID: Fixture.ny.id)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, WidgetSnapshot.fileName(placeID: Fixture.la.id))
        XCTAssertFalse(a.contains("Los") || a.contains("34") || a.contains("118"))
    }
}

final class AppIconTests: XCTestCase {
    func testOnlyTheOriginalIconIsFree() {
        XCTAssertEqual(AppIcon.allCases.filter { !$0.isPremium }, [.night])
        XCTAssertNil(AppIcon.night.alternateName)
    }

    func testNamesMatchTheIconSetsInTheAssetCatalog() {
        XCTAssertEqual(AppIcon.allCases.compactMap(\.alternateName), ["AppIcon-Aurora", "AppIcon-Storm", "AppIcon-Sunset"])
        XCTAssertEqual(AppIcon.named("AppIcon-Storm"), .storm)
        XCTAssertEqual(AppIcon.named(nil), .night)
        XCTAssertEqual(AppIcon.named("Something else"), .night)
        for icon in AppIcon.allCases {
            XCTAssertNotNil(UIImage(named: icon.previewImage), icon.previewImage)
        }
    }
}

@MainActor
final class OverviewTests: XCTestCase {
    func testEveryPlaceLoadsAndOneFailureDoesNotHideTheRest() async {
        let weather = FakeWeather()
        weather.failures["New York"] = .offline
        let model = OverviewModel()
        var written: [String] = []
        await model.load([Fixture.la, Fixture.ny], repository: weather) { written.append($0.place.name) }
        XCTAssertNotNil(model.forecasts[Fixture.la.id])
        XCTAssertNil(model.forecasts[Fixture.ny.id])
        XCTAssertEqual(model.failed, [Fixture.ny.id])
        XCTAssertEqual(written, ["Los Angeles"])
        XCTAssertFalse(model.isLoading)
    }

    func testASavedForecastStaysWhenTheRefreshFails() async {
        let weather = FakeWeather()
        weather.cachedPlaces = ["New York"]
        weather.failures["New York"] = .offline
        let model = OverviewModel()
        await model.load([Fixture.ny], repository: weather)
        XCTAssertEqual(model.forecasts[Fixture.ny.id]?.isCached, true)
    }

    func testTimeDifferenceWording() {
        let winter = Fixture.date(2026, 1, 15)
        let la = TimeZone(identifier: "America/Los_Angeles")!
        XCTAssertEqual(PlacesOverviewText.offset(TimeZone(identifier: "America/New_York")!, at: winter, home: la), "3 HR AHEAD")
        XCTAssertEqual(PlacesOverviewText.offset(TimeZone(identifier: "Pacific/Honolulu")!, at: winter, home: la), "2 HR BEHIND")
        XCTAssertEqual(PlacesOverviewText.offset(la, at: winter, home: la), "SAME TIME AS YOU")
        XCTAssertTrue(PlacesOverviewText.offset(TimeZone(identifier: "Asia/Kolkata")!, at: winter, home: TimeZone(identifier: "Europe/London")!).hasPrefix("5"))
    }
}
