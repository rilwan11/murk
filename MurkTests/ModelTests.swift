import XCTest
@testable import Murk

final class UnitAndCodeTests: XCTestCase {
    func testTemperature() {
        XCTAssertEqual(TempUnit.fahrenheit.temp(0), 32)
        XCTAssertEqual(TempUnit.fahrenheit.temp(100), 212)
        XCTAssertEqual(TempUnit.fahrenheit.temp(-40), -40)
        XCTAssertEqual(TempUnit.celsius.temp(19.6), 20)
    }

    func testWind() {
        XCTAssertEqual(TempUnit.fahrenheit.wind(100), "62 MPH")
        XCTAssertEqual(TempUnit.celsius.wind(99.6), "100 KM/H")
        XCTAssertEqual(TempUnit.fahrenheit.windValue(100), 62.1371, accuracy: 0.001)
    }

    func testWeatherCodes() {
        XCTAssertEqual(Condition(code: 0, isDay: true).title, "Sunny")
        XCTAssertEqual(Condition(code: 0, isDay: false).title, "Clear")
        XCTAssertEqual(Condition(code: 63, isDay: true).precip, .rain)
        XCTAssertEqual(Condition(code: 73, isDay: true).precip, .snow)
        XCTAssertEqual(Condition(code: 3, isDay: true).precip, .none)
        XCTAssertEqual(Condition(code: 95, isDay: true).symbol, "cloud.bolt.rain.fill")
        XCTAssertEqual(Condition(code: 95, isDay: true).cloudCover, 1)
        XCTAssertEqual(Condition(code: 65, isDay: true).intensity, 1)
        XCTAssertEqual(ArtKind(code: 61), .rain)
        XCTAssertEqual(ArtKind(code: 0), .clear)
        // Every code has a name and a symbol.
        for code in [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99] {
            XCTAssertNotEqual(Condition(code: code, isDay: true).title, "—", "code \(code)")
            XCTAssertFalse(Condition(code: code, isDay: true).symbol.isEmpty)
        }
    }

    func testCompassAndAQI() {
        XCTAssertEqual(0.0.compassDirection, "N")
        XCTAssertEqual(270.0.compassDirection, "W")
        XCTAssertEqual(359.0.compassDirection, "N")
        XCTAssertEqual(aqiLabel(42), "GOOD")
        XCTAssertEqual(aqiLabel(160), "UNHEALTHY")
    }

    func testFreshness() {
        let now = Date()
        var f = Fixture.forecast(now: now)
        XCTAssertFalse(f.isStale(now: now.addingTimeInterval(1800)))
        XCTAssertTrue(f.isStale(now: now.addingTimeInterval(2 * 3600)))
        f.fetchedAt = now.addingTimeInterval(60)
        XCTAssertEqual(f.age(now: now), 0)      // never negative
    }

    func testPlaceIDIsLocaleIndependent() {
        XCTAssertEqual(Fixture.la.id, "Los Angeles|34.052|-118.244")
    }
}

final class OutlookTests: XCTestCase {
    func testAgeWording() {
        XCTAssertEqual(Outlook.age(10), "JUST NOW")
        XCTAssertEqual(Outlook.age(12 * 60), "12 MIN AGO")
        XCTAssertEqual(Outlook.age(3 * 3600 + 5), "3 HR AGO")
        XCTAssertEqual(Outlook.age(72 * 3600), "3 DAYS AGO")
    }

    func testRainComingIsCalledOut() {
        let now = Fixture.date(2026, 6, 10, 9)
        let f = Fixture.forecast(now: now, rainFromHour: 14)
        let s = Outlook.summary(f, unit: .fahrenheit, now: now)
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.hasPrefix("RAIN LIKELY AROUND"), s!)
    }

    func testQuietDayStillMentionsTheSwing() {
        let now = Fixture.date(2026, 6, 10, 15)       // warmest part of the fixture's day
        let f = Fixture.forecast(now: now)
        // Current 19.4°C; the fixture bottoms out near 9°C overnight: more than 10°F cooler.
        let s = Outlook.summary(f, unit: .fahrenheit, now: now)
        XCTAssertNotNil(s)
        XCTAssertTrue(s!.contains("COOLER BY"), s!)
    }

    func testNothingToSayWithoutHourlyData() {
        var f = Fixture.forecast()
        f.hourly = []
        XCTAssertNil(Outlook.summary(f, unit: .celsius))
    }
}

final class ContrastTests: XCTestCase {
    func testEverySkinIsReadable() {
        for skin in Skin.allCases {
            XCTAssertGreaterThanOrEqual(Contrast.ratio(skin.inkHex, skin.bgHex), 7, "\(skin) text")
            XCTAssertGreaterThanOrEqual(Contrast.ratio(skin.mutedHex, skin.bgHex), 3, "\(skin) secondary text")
        }
    }

    func testTextStaysReadableOnEverySky() {
        func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 { Sky.lerp(a, b, t) }
        for alt in [-90.0, -12, -6, -3, -1, 0, 2, 3, 4, 6, 10, 18, 30, 45, 70] {
            for cover in [0.0, 0.3, 0.55, 0.7, 0.8, 0.85, 0.9, 1] {
                let sky = Sky.at(altitude: alt, cover: cover, precip: false)
                let ink: UInt32 = sky.bright ? 0x13233D : 0xFFFFFF
                // Cards put a white (bright) or black (dark) wash under the text.
                let card = sky.bright ? blend(sky.bottom, 0xFFFFFF, 0.5) : blend(sky.bottom, 0x000000, 0.2)
                XCTAssertGreaterThanOrEqual(Contrast.ratio(ink, sky.mid), 3, "sun \(alt)°, cover \(cover): on the sky")
                XCTAssertGreaterThanOrEqual(Contrast.ratio(ink, card), 3, "sun \(alt)°, cover \(cover): on a card")
            }
        }
    }

    func testContrastMath() {
        XCTAssertEqual(Contrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(0x777777, 0x777777), 1, accuracy: 0.001)
    }
}

final class ProTests: XCTestCase {
    private let now = Date()

    func testActive() {
        XCTAssertTrue(ProStatus.isActive([ProTransaction(productID: ProStatus.monthlyID, expirationDate: now.addingTimeInterval(86_400))], now: now))
        XCTAssertTrue(ProStatus.isActive([ProTransaction(productID: ProStatus.annualID, expirationDate: now.addingTimeInterval(86_400))], now: now))
    }

    func testExpired() {
        XCTAssertFalse(ProStatus.isActive([ProTransaction(productID: ProStatus.monthlyID, expirationDate: now.addingTimeInterval(-1))], now: now))
    }

    func testRevoked() {
        XCTAssertFalse(ProStatus.isActive([ProTransaction(productID: ProStatus.annualID, expirationDate: now.addingTimeInterval(86_400), revocationDate: now)], now: now))
    }

    func testUpgradedMonthlyIsReplacedByAnnual() {
        let monthly = ProTransaction(productID: ProStatus.monthlyID, expirationDate: now.addingTimeInterval(86_400), isUpgraded: true)
        XCTAssertFalse(ProStatus.isActive([monthly], now: now))
        let annual = ProTransaction(productID: ProStatus.annualID, expirationDate: now.addingTimeInterval(86_400 * 300))
        XCTAssertTrue(ProStatus.isActive([monthly, annual], now: now))
    }

    func testNothingAndUnknownProducts() {
        XCTAssertFalse(ProStatus.isActive([], now: now))
        XCTAssertFalse(ProStatus.isActive([ProTransaction(productID: "com.other.thing", expirationDate: now.addingTimeInterval(86_400))], now: now))
    }

    @MainActor
    func testStoreCachesAndReportsChanges() {
        let d = Fixture.defaults()
        let store = EntitlementStore(defaults: d)
        XCTAssertFalse(store.isPro)
        var seen: [Bool] = []
        store.onChange = { seen.append($0) }
        store.apply(true)             // purchase or restore confirmed
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(d.bool(forKey: ProStatus.cacheKey))
        XCTAssertTrue(EntitlementStore(defaults: d).isPro)       // there at next launch, before the App Store answers
        store.apply(false)            // expired or refunded
        XCTAssertFalse(store.isPro)
        XCTAssertEqual(seen, [true, false])
    }

    @MainActor
    func testFreeTierAllowsOneSavedCity() {
        let state = makeState(places: [])
        XCTAssertTrue(state.add(Fixture.la))
        XCTAssertNil(state.paywall)
        XCTAssertFalse(state.add(Fixture.ny))                    // the second city is the paywall moment
        XCTAssertEqual(state.paywall, .city)
        XCTAssertEqual(state.places.count, 1)
        state.paywall = nil
        state.setPro(true)
        XCTAssertTrue(state.add(Fixture.ny))
        XCTAssertEqual(state.places.count, 2)
    }

    @MainActor
    func testPremiumSkinsAreGatedAndBasicWeatherIsNot() async {
        let state = makeState()
        state.choose(.aurora)
        XCTAssertEqual(state.paywall, .skin)
        XCTAssertNotEqual(state.skin, .aurora)
        state.paywall = nil
        state.choose(.fog)                                       // free skin
        XCTAssertEqual(state.skin, .fog)
        XCTAssertNil(state.paywall)
        state.choose(nil)                                        // Auto is Pro
        XCTAssertEqual(state.paywall, .skin)
        state.paywall = nil

        state.useLocation = false
        state.select(Fixture.ny)                                 // existing saved cities keep working for free
        await pause(0.2)
        XCTAssertEqual(state.forecast?.place.name, "New York")
        XCTAssertNil(state.paywall)
    }

    @MainActor
    func testLosingProFallsBackToFreeLooksAndKeepsCities() {
        let state = makeState()
        state.setPro(true)
        state.choose(.storm)
        XCTAssertEqual(state.skin, .storm)
        state.setPro(false)
        XCTAssertEqual(state.skin, .graphite)
        XCTAssertFalse(state.autoSkin)
        XCTAssertEqual(state.places.count, 2)
    }

    func testFreeSkinsExist() {
        XCTAssertEqual(Skin.allCases.filter { !$0.isPremium }.count, 3)
        XCTAssertFalse(Skin.graphite.isPremium)
    }
}
