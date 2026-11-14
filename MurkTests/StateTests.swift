import XCTest
@testable import Murk

@MainActor
final class StaleRequestTests: XCTestCase {
    func testSlowFailureForOldCityNeverReachesTheScreen() async {
        let weather = FakeWeather()
        weather.delays = ["Los Angeles": 0.4, "New York": 0.05]
        weather.failures = ["Los Angeles": .offline]
        let state = makeState(weather: weather)
        state.useLocation = false

        state.select(Fixture.la)
        state.select(Fixture.ny)          // switch before the first answer arrives
        await wait(0.8)

        XCTAssertEqual(state.forecast?.place.name, "New York")
        XCTAssertNil(state.failure)       // Los Angeles's error was dropped
        XCTAssertFalse(state.isLoading)
    }

    func testSlowSuccessForOldCityNeverReplacesTheNewOne() async {
        let weather = FakeWeather()
        weather.delays = ["Los Angeles": 0.4, "New York": 0.05]
        let state = makeState(weather: weather)
        state.useLocation = false

        state.select(Fixture.la)
        state.select(Fixture.ny)
        await wait(0.8)
        XCTAssertEqual(state.forecast?.place.name, "New York")
        XCTAssertEqual(state.forecast?.aqi, 42)       // optional data attached to the right city
    }

    func testLoadingStaysOnWhileTheNewestRequestRuns() async {
        let weather = FakeWeather()
        weather.delays = ["Los Angeles": 0.05, "New York": 0.5]
        let state = makeState(weather: weather)
        state.useLocation = false

        state.select(Fixture.la)
        state.select(Fixture.ny)
        await wait(0.25)                  // the old request has finished; the new one hasn't
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.forecast)      // not Los Angeles's weather under New York's name
        await wait(0.6)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.forecast?.place.name, "New York")
    }

    func testRapidSwitchingWhileOfflineEndsOnTheLastCity() async {
        let weather = FakeWeather()
        weather.failures = ["Los Angeles": .offline, "New York": .offline]
        weather.cachedPlaces = ["New York"]
        let state = makeState(weather: weather)
        state.useLocation = false

        for _ in 0..<5 { state.select(Fixture.la); state.select(Fixture.ny) }
        await wait(0.4)
        XCTAssertEqual(state.failure, .offline)
        XCTAssertEqual(state.forecast?.place.name, "New York")     // the saved forecast stays on screen
        XCTAssertEqual(state.forecast?.isCached, true)
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.status()?.canRetry, true)
        XCTAssertTrue(state.status()!.text.contains("OFFLINE"))
    }

    func testForegroundingDoesNotStartDuplicateWork() async {
        let weather = FakeWeather()
        weather.delays = ["Los Angeles": 0.2]
        let state = makeState(weather: weather)
        state.useLocation = false
        state.select(Fixture.la)
        state.refreshIfStale(); state.refreshIfStale(); state.refreshIfStale()     // while loading
        await wait(0.5)
        XCTAssertEqual(weather.coreCalls, 1)
        state.refreshIfStale()                                                    // fresh forecast: nothing to do
        await wait(0.1)
        XCTAssertEqual(weather.coreCalls, 1)
    }

    func testCachedForecastShowsImmediatelyThenRefreshes() async {
        let weather = FakeWeather()
        weather.delays = ["Los Angeles": 0.3]
        weather.cachedPlaces = ["Los Angeles"]
        let state = makeState(weather: weather)
        state.useLocation = false
        state.select(Fixture.la)
        await wait(0.1)
        XCTAssertEqual(state.forecast?.isCached, true)
        XCTAssertTrue(state.isLoading)
        XCTAssertTrue(state.status()!.text.contains("REFRESHING"))
        await wait(0.5)
        XCTAssertEqual(state.forecast?.isCached, false)
        XCTAssertTrue(state.status()!.text.contains("UPDATED"))
    }
}

@MainActor
final class LocationStateTests: XCTestCase {
    func testLocationIsNotRequestedUntilTheUserAsks() async {
        let location = FakeLocation(); location.isAuthorized = false
        let state = makeState(location: location)
        XCTAssertFalse(state.useLocation)
        await state.start()
        XCTAssertEqual(location.calls, 0)
        XCTAssertEqual(state.forecast?.place.name, "Los Angeles")
        XCTAssertFalse(state.isFollowingLocation)

        state.selectCurrentLocation()
        await wait(0.3)
        XCTAssertEqual(location.calls, 1)
        XCTAssertTrue(state.isFollowingLocation)
        XCTAssertEqual(state.forecast?.place.name, "Here")
    }

    func testTimeoutFallsBackToSavedCityAndSaysSo() async {
        let location = FakeLocation(); location.result = .failure(LocationError.timedOut)
        let state = makeState(location: location)
        await state.start()
        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.locationProblem, .timedOut)
        XCTAssertFalse(state.isFollowingLocation)             // no claim to be tracking
        XCTAssertEqual(state.fallbackPlace?.name, "Los Angeles")
        XCTAssertEqual(state.forecast?.place.name, "Los Angeles")
        XCTAssertFalse(state.forecast!.place.isCurrentLocation)
    }

    func testDeniedKeepsSavedCitiesWorking() async {
        let location = FakeLocation(); location.isDenied = true; location.result = .failure(LocationError.denied)
        let state = makeState(location: location)
        await state.start()
        XCTAssertTrue(state.locationDenied)
        XCTAssertEqual(state.locationProblem, .denied)
        XCTAssertEqual(state.cityIDs.count, 2)                // current location is not offered in the swipe order
        state.select(Fixture.ny)
        await wait(0.2)
        XCTAssertEqual(state.forecast?.place.name, "New York")
    }

    func testNoPlacesAtAllLeavesNoSpinner() async {
        let location = FakeLocation(); location.isAuthorized = false
        let state = makeState(location: location, places: [])
        await state.start()
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.forecast)
        XCTAssertNil(state.activePlace)
    }
}

final class DeadlineTests: XCTestCase {
    func testTimesOut() async {
        let start = Date()
        do {
            let _: Int = try await Deadline.run(seconds: 0.15) { _ in }      // never answers
            XCTFail("should time out")
        } catch { XCTAssertTrue(error is Deadline.TimedOut) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testResumesExactlyOnce() async throws {
        var later: OneShot<Int>?
        let v: Int = try await Deadline.run(seconds: 1) { shot in
            later = shot
            XCTAssertTrue(shot.resume(with: .success(7)))
            XCTAssertFalse(shot.resume(with: .success(8)))               // ignored
            XCTAssertFalse(shot.resume(with: .failure(Deadline.TimedOut())))
        }
        XCTAssertEqual(v, 7)
        await wait(0.05)
        XCTAssertEqual(later?.isFinished, true)
        XCTAssertEqual(later?.resume(with: .success(9)), false)
    }

    func testCancellationEndsTheWait() async {
        let task = Task { () -> Int in try await Deadline.run(seconds: 30) { _ in } }
        await wait(0.05)
        task.cancel()
        let start = Date()
        do { _ = try await task.value; XCTFail("should be cancelled") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testCleanupRunsOnce() async {
        final class Box: @unchecked Sendable { var n = 0 }
        let box = Box()
        _ = try? await Deadline.run(seconds: 0.05) { (shot: OneShot<Int>) in shot.onFinish { box.n += 1 } }
        await wait(0.1)
        XCTAssertEqual(box.n, 1)
    }

    func testRepeatedRequestsDoNotLeak() async {
        for i in 0..<50 {
            let v: Int? = try? await Deadline.run(seconds: 1) { shot in shot.resume(with: .success(i)) }
            XCTAssertEqual(v, i)
        }
    }
}

final class AlertTests: XCTestCase {
    func testSameAlertIsClaimedOnce() {
        let ledger = AlertLedger(defaults: Fixture.defaults())
        XCTAssertEqual(ledger.claim(["a", "b"], scope: "city|LA"), ["a", "b"])
        XCTAssertEqual(ledger.claim(["a", "b", "c"], scope: "city|LA"), ["c"])
        XCTAssertEqual(ledger.claim(["a", "a"], scope: "city|X"), ["a"])
    }

    func testDistinctPlacesEachGetTheAlert() {
        let ledger = AlertLedger(defaults: Fixture.defaults())
        XCTAssertEqual(ledger.claim(["a"], scope: "city|LA"), ["a"])
        XCTAssertEqual(ledger.claim(["a"], scope: "city|NY"), ["a"])
        XCTAssertEqual(ledger.claim(["a"], scope: "city|NY"), [])
    }

    func testOldIDsExpireOnSchedule() {
        var ledger = AlertLedger(defaults: Fixture.defaults())
        ledger.lifetime = 100
        let t = Date()
        XCTAssertEqual(ledger.claim(["a"], scope: "s", now: t), ["a"])
        XCTAssertEqual(ledger.claim(["a"], scope: "s", now: t.addingTimeInterval(99)), [])
        XCTAssertEqual(ledger.claim(["a"], scope: "s", now: t.addingTimeInterval(101)), ["a"])
    }

    func testTrimmingDropsTheOldestFirst() {
        var ledger = AlertLedger(defaults: Fixture.defaults())
        ledger.capacity = 3
        let t = Date()
        for (i, id) in ["a", "b", "c", "d", "e"].enumerated() {
            _ = ledger.claim([id], scope: "s", now: t.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(ledger.count, 3)
        let now = t.addingTimeInterval(10)
        XCTAssertFalse(ledger.contains("a", scope: "s", now: now))
        XCTAssertFalse(ledger.contains("b", scope: "s", now: now))
        XCTAssertTrue(ledger.contains("c", scope: "s", now: now))
        XCTAssertTrue(ledger.contains("e", scope: "s", now: now))
    }

    func testIDsFromThePreviousFormatAreStillRemembered() {
        let d = Fixture.defaults()
        d.set(["old1", "old2"], forKey: "seenAlerts")
        let ledger = AlertLedger(defaults: d)
        XCTAssertEqual(ledger.claim(["old1", "new"], scope: "city|LA"), ["new"])
        XCTAssertNil(d.stringArray(forKey: "seenAlerts"))
    }

    func testForegroundAndBackgroundShareOneRecord() {
        let d = Fixture.defaults()
        var f = Fixture.forecast()
        f.alerts = [WeatherAlert(id: "urn:1", event: "Flood Warning", headline: "Flooding", severity: "Severe")]
        var rules = NotificationRules(); rules.official = true
        var posted: [String] = []
        let post: AlertDispatcher.Post = { id, _, _ in posted.append(id) }
        // First delivery (say, in the app), then again (say, in the background): one notification.
        XCTAssertEqual(AlertDispatcher.deliver(for: f, rules: rules, unit: .fahrenheit, isPro: false, ledger: AlertLedger(defaults: d), post: post), ["urn:1"])
        XCTAssertEqual(AlertDispatcher.deliver(for: f, rules: rules, unit: .fahrenheit, isPro: false, ledger: AlertLedger(defaults: d), post: post), [])
        XCTAssertEqual(posted.count, 1)
    }

    func testNothingIsPostedUnlessTheUserTurnedItOn() {
        var f = Fixture.forecast()
        f.alerts = [WeatherAlert(id: "urn:1", event: "Flood Warning", headline: "Flooding", severity: "Severe")]
        var posted = 0
        let out = AlertDispatcher.deliver(for: f, rules: NotificationRules(), unit: .fahrenheit, isPro: true,
                                          ledger: AlertLedger(defaults: Fixture.defaults())) { _, _, _ in posted += 1 }
        XCTAssertTrue(out.isEmpty)
        XCTAssertEqual(posted, 0)
    }

    func testAdvancedRulesNeedProAndFireOncePerDay() {
        let now = Fixture.date(2026, 6, 10, 9)
        var f = Fixture.forecast(now: now, rainFromHour: 13)
        f.aqi = 160
        var rules = NotificationRules(); rules.rain = true; rules.aqi = true; rules.wind = true; rules.gustKmh = 90
        XCTAssertTrue(rules.notices(for: f, unit: .fahrenheit, advanced: false, now: now).isEmpty)
        let notices = rules.notices(for: f, unit: .fahrenheit, advanced: true, now: now)
        XCTAssertEqual(notices.map(\.id), ["rule.rain.2026-6-10", "rule.aqi.2026-6-10"])      // gusts of 22 don't reach 90

        let d = Fixture.defaults()
        var posted = 0
        let post: AlertDispatcher.Post = { _, _, _ in posted += 1 }
        _ = AlertDispatcher.deliver(for: f, rules: rules, unit: .fahrenheit, isPro: true, ledger: AlertLedger(defaults: d), now: now, post: post)
        _ = AlertDispatcher.deliver(for: f, rules: rules, unit: .fahrenheit, isPro: true, ledger: AlertLedger(defaults: d), now: now.addingTimeInterval(3600), post: post)
        XCTAssertEqual(posted, 2)
    }

    func testRulesSaveAndLoad() {
        let d = Fixture.defaults()
        XCTAssertEqual(NotificationRules.load(d), NotificationRules())
        var r = NotificationRules(); r.official = true; r.rainChance = 80
        r.save(d)
        XCTAssertEqual(NotificationRules.load(d), r)
    }
}

final class DeepLinkTests: XCTestCase {
    func testKnownLinks() {
        XCTAssertEqual(DeepLink(url: URL(string: "murk://now")!), .page(0))
        XCTAssertEqual(DeepLink(url: URL(string: "murk://air")!), .page(1))
        XCTAssertEqual(DeepLink(url: URL(string: "murk://rain")!), .page(2))
        XCTAssertEqual(DeepLink(url: URL(string: "murk://sun")!), .page(3))
        XCTAssertEqual(DeepLink(url: URL(string: "murk://moon")!), .page(4))
        XCTAssertEqual(DeepLink(url: URL(string: "murk://settings")!), .settings)
        XCTAssertEqual(DeepLink(url: URL(string: "MURK://NOW")!), .page(0))
        XCTAssertEqual(DeepLink(url: URL(string: "murk:///rain")!), .page(2))
        XCTAssertEqual(DeepLink.page(1).url.absoluteString, "murk://air")
    }

    func testInvalidLinksAreRejected() {
        for bad in ["murk://", "murk://nope", "murk://now/../../etc", "https://now", "other://now", "murk://%00", "murk://settings2"] {
            guard let url = URL(string: bad) else { continue }
            if bad == "murk://now/../../etc" { XCTAssertEqual(DeepLink(url: url), .page(0)); continue }   // host is still "now"
            XCTAssertNil(DeepLink(url: url), bad)
        }
    }

    @MainActor
    func testStateIgnoresBadLinksAndRoutesGoodOnes() {
        let state = makeState()
        state.open(URL(string: "murk://garbage")!)
        XCTAssertNil(state.route)
        state.open(URL(string: "murk://now")!)
        XCTAssertEqual(state.route, .page(0))
    }
}
