import XCTest
@testable import Murk

final class CoordinateAndURLTests: XCTestCase {
    func testCoordinatesAlwaysUseADecimalPoint() {
        XCTAssertEqual(Coordinate.string(48.8566, places: 2), "48.86")
        XCTAssertEqual(Coordinate.string(-0.1278, places: 2), "-0.13")
        XCTAssertEqual(Coordinate.string(48.8566, places: 1), "48.9")
        // The same number formatted for Germany uses a comma, which is what the POSIX locale protects against.
        XCTAssertEqual(String(format: "%.2f", locale: Locale(identifier: "de_DE"), 48.8566), "48,86")
    }

    func testForecastURL() {
        let url = WeatherAPI.forecastURL(Fixture.la, config: .openMeteoFree)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func v(_ n: String) -> String? { items.first { $0.name == n }?.value }
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(v("latitude"), "34.05")
        XCTAssertEqual(v("longitude"), "-118.24")
        XCTAssertEqual(v("timezone"), "auto")
        XCTAssertNotNil(v("minutely_15"))
        XCTAssertNil(v("apikey"))
        let light = WeatherAPI.forecastURL(Fixture.la, light: true, config: .openMeteoFree)
        XCTAssertFalse(light.absoluteString.contains("minutely_15"))
    }

    func testApproximateModeSendsOneDecimalPlace() {
        let url = WeatherAPI.forecastURL(Fixture.la, places: 1, config: .openMeteoFree)
        XCTAssertTrue(url.query!.contains("latitude=34.1"))
        XCTAssertTrue(url.query!.contains("longitude=-118.2"))
    }

    func testCommercialProviderURL() {
        let c = ProviderConfig.openMeteoCommercial(apiKey: "KEY123")
        XCTAssertTrue(c.isCommercial)
        let f = WeatherAPI.forecastURL(Fixture.la, config: c)
        XCTAssertEqual(f.host, "customer-api.open-meteo.com")
        XCTAssertTrue(f.query!.contains("apikey=KEY123"))
        let a = WeatherAPI.airQualityURL(Fixture.la, config: c)
        XCTAssertEqual(a.host, "customer-air-quality-api.open-meteo.com")
        XCTAssertTrue(a.query!.contains("apikey=KEY123"))
        XCTAssertFalse(ProviderConfig.openMeteoFree.isCommercial)
    }

    func testAlertsAndAirQualityURLs() {
        let alerts = WeatherAPI.alertsURL(Fixture.ny, config: .openMeteoFree)
        XCTAssertEqual(alerts.host, "api.weather.gov")
        XCTAssertTrue(alerts.absoluteString.contains("40.71"))
        XCTAssertTrue(alerts.absoluteString.contains("-74.01"))
        let air = WeatherAPI.airQualityURL(Fixture.ny, config: .openMeteoFree)
        XCTAssertTrue(air.query!.contains("latitude=40.71"))
    }
}

final class ParsingTests: XCTestCase {
    func testOpenMeteoParsing() throws {
        let now = Fixture.date(2026, 6, 10, 14)
        let f = try WeatherAPI.parseForecast(DebugStubs.openMeteoJSON(now: now), place: Fixture.la, fetchedAt: now)
        XCTAssertEqual(f.daily.count, 8)
        XCTAssertEqual(f.hourly.count, 192)
        XCTAssertEqual(f.minutely.count, 12)
        XCTAssertEqual(f.current.temperature, 19.4, accuracy: 0.001)
        XCTAssertEqual(f.current.code, 2)
        XCTAssertTrue(f.current.isDay)
        XCTAssertEqual(f.daily[1].precipChance, 45)
        XCTAssertEqual(f.timeZone.identifier, "America/Los_Angeles")
        XCTAssertFalse(f.isCached)
        XCTAssertEqual(f.hourly[0].windGust, 22)
    }

    func testTimesAreReadInThePlacesOwnZone() throws {
        let now = Fixture.date(2026, 6, 10, 14)
        let f = try WeatherAPI.parseForecast(DebugStubs.openMeteoJSON(now: now), place: Fixture.la, fetchedAt: now)
        // Midnight and 6:30 sunrise in Los Angeles, whatever zone the test machine is in.
        XCTAssertEqual(f.daily[0].date, Fixture.date(2026, 6, 10, 0))
        XCTAssertEqual(f.daily[0].sunrise, Fixture.date(2026, 6, 10, 6).addingTimeInterval(1800))
        XCTAssertEqual(f.hourly[0].time, Fixture.date(2026, 6, 10, 0))
    }

    func testDaylightSavingDay() throws {
        // Clocks jump from 2:00 to 3:00 in New York on 8 March 2026.
        let now = Fixture.date(2026, 3, 8, 12, zone: "America/New_York")
        let data = DebugStubs.openMeteoJSON(now: now, timeZone: "America/New_York")
        let f = try WeatherAPI.parseForecast(data, place: Fixture.ny, fetchedAt: now)
        XCTAssertEqual(f.hourly.count, 192)
        for i in 1..<f.hourly.count { XCTAssertEqual(f.hourly[i].time.timeIntervalSince(f.hourly[i - 1].time), 3600, accuracy: 0.5) }
        XCTAssertEqual(f.daily[1].date.timeIntervalSince(f.daily[0].date), 23 * 3600, accuracy: 0.5)
    }

    func testIncompleteResponseThrows() {
        let data = Data("{\"utc_offset_seconds\":0,\"timezone\":\"GMT\"}".utf8)
        XCTAssertThrowsError(try WeatherAPI.parseForecast(data, place: Fixture.la, fetchedAt: Date()))
    }

    func testNWSAlertParsing() throws {
        let now = Fixture.date(2026, 6, 10, 12)
        let json = """
        {"features":[
          {"id":"urn:a","properties":{"id":"urn:a","event":"Flood Warning","headline":"Flood Warning until 6 PM","severity":"Severe","ends":"2026-06-10T18:00:00-07:00","description":"River rising.","instruction":"Move to higher ground."}},
          {"id":"urn:b","properties":{"id":"urn:b","event":"Wind Advisory","headline":"Old","severity":"Minor","ends":"2026-06-09T18:00:00-07:00"}},
          {"id":"urn:c","properties":{"event":null}}
        ]}
        """
        let alerts = try WeatherAPI.parseAlerts(Data(json.utf8), now: now)
        XCTAssertEqual(alerts.map(\.id), ["urn:a"])            // ended and nameless alerts are dropped
        XCTAssertEqual(alerts[0].event, "Flood Warning")
        XCTAssertTrue(alerts[0].isSevere)
        XCTAssertEqual(alerts[0].instruction, "Move to higher ground.")
        XCTAssertEqual(alerts[0].ends, Fixture.date(2026, 6, 10, 18))
    }

    func testAQIParsing() throws {
        XCTAssertEqual(try WeatherAPI.parseAQI(Data("{\"current\":{\"us_aqi\":57.6}}".utf8)), 58)
        XCTAssertNil(try WeatherAPI.parseAQI(Data("{}".utf8)))
    }
}

final class CacheTests: XCTestCase {
    func testSaveAndLoad() {
        let cache = ForecastCache(directory: Fixture.tempDir())
        let body = Data("hello".utf8), t = Date()
        cache.save(body, for: Fixture.la, at: t)
        let hit = cache.load(for: Fixture.la, now: t.addingTimeInterval(60))
        XCTAssertEqual(hit?.body, body)
        XCTAssertEqual(hit!.savedAt.timeIntervalSince1970, t.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(cache.load(for: Fixture.ny))
    }

    func testExpiry() {
        let cache = ForecastCache(directory: Fixture.tempDir())
        let t = Date()
        cache.save(Data("x".utf8), for: Fixture.la, at: t)
        XCTAssertNotNil(cache.load(for: Fixture.la, now: t.addingTimeInterval(47 * 3600)))
        XCTAssertNil(cache.load(for: Fixture.la, now: t.addingTimeInterval(49 * 3600)))
        // An expired entry is deleted, not just ignored.
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.url(for: Fixture.la).path))
    }

    func testOldVersionIsDiscarded() throws {
        let cache = ForecastCache(directory: Fixture.tempDir())
        let old = ForecastCache.Entry(version: ForecastCache.version - 1, savedAt: Date(), body: Data("x".utf8))
        try JSONEncoder().encode(old).write(to: cache.url(for: Fixture.la))
        XCTAssertNil(cache.load(for: Fixture.la))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.url(for: Fixture.la).path))
    }

    func testFileNamesRevealNothing() {
        let key = ForecastCache.key(latitude: 34.0522, longitude: -118.2437)
        XCTAssertEqual(key, ForecastCache.key(latitude: 34.0519, longitude: -118.2441))   // same ~1 km cell
        XCTAssertNotEqual(key, ForecastCache.key(latitude: 40.7128, longitude: -74.0060))
        XCTAssertFalse(key.contains("34.05"))
        XCTAssertFalse(key.contains("118.24"))
        XCTAssertFalse(key.contains("."))
        XCTAssertEqual(key.count, 24)
    }

    func testStorageIsBounded() {
        var cache = ForecastCache(directory: Fixture.tempDir())
        cache.maxEntries = 3
        let t = Date()
        for i in 0..<6 {
            cache.save(Data("x".utf8), for: Place(name: "P\(i)", latitude: Double(i), longitude: 0), at: t.addingTimeInterval(Double(i)))
        }
        let files = try! FileManager.default.contentsOfDirectory(atPath: cache.directory.path)
        XCTAssertEqual(files.count, 3)
        // The newest three survive.
        XCTAssertNotNil(cache.load(for: Place(name: "P5", latitude: 5, longitude: 0), now: t.addingTimeInterval(10)))
        XCTAssertNil(cache.load(for: Place(name: "P0", latitude: 0, longitude: 0), now: t.addingTimeInterval(10)))
    }
}

final class RepositoryTests: XCTestCase {
    private func repo(_ fetch: @escaping HTTPFetch, events: EventLog? = nil) -> WeatherRepository {
        var r = WeatherRepository()
        r.config = .openMeteoFree
        r.cache = ForecastCache(directory: Fixture.tempDir())
        r.coordinatePlaces = { 2 }
        r.fetch = fetch
        if let events { r.onEvent = { events.add($0) } }
        return r
    }

    final class EventLog: @unchecked Sendable {
        private let lock = NSLock(); private var list: [WeatherRepository.Event] = []
        func add(_ e: WeatherRepository.Event) { lock.lock(); list.append(e); lock.unlock() }
        var all: [WeatherRepository.Event] { lock.lock(); defer { lock.unlock() }; return list }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock(); private var n = 0
        func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    func testCoreLoadsAndCaches() async throws {
        let r = repo { req in (DebugStubs.openMeteoJSON(), Fixture.response(req.url!)) }
        XCTAssertNil(r.cached(for: Fixture.la))
        let f = try await r.core(for: Fixture.la)
        XCTAssertFalse(f.isCached)
        let c = r.cached(for: Fixture.la)
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.isCached, true)
        XCTAssertEqual(c?.daily.count, 8)
    }

    func testSlowNetworkRetriesOnceWithLighterRequest() async throws {
        let calls = Counter(), log = EventLog()
        let r = repo({ req in
            if calls.next() == 1 { throw URLError(.timedOut) }
            XCTAssertFalse(req.url!.absoluteString.contains("minutely_15"))
            return (DebugStubs.openMeteoJSON(), Fixture.response(req.url!))
        }, events: log)
        _ = try await r.core(for: Fixture.la)
        XCTAssertEqual(calls.value, 2)
        XCTAssertTrue(log.all.contains(.retry(kind: "forecast")))
    }

    func testOfflineFailsFastWithoutRetry() async {
        let calls = Counter()
        let r = repo { _ in _ = calls.next(); throw URLError(.notConnectedToInternet) }
        do { _ = try await r.core(for: Fixture.la); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? WeatherError, .offline) }
        XCTAssertEqual(calls.value, 1)
    }

    func testProviderErrorIsReported() async {
        let r = repo { req in (Data("{\"reason\":\"Too many requests\"}".utf8), Fixture.response(req.url!, 429)) }
        do { _ = try await r.core(for: Fixture.la); XCTFail("should throw") }
        catch { XCTAssertEqual(error as? WeatherError, .provider(status: 429, reason: "Too many requests")) }
    }

    func testCancelledRequestIsCancellationNotAnError() async {
        let r = repo { _ in throw URLError(.cancelled) }
        do { _ = try await r.core(for: Fixture.la); XCTFail("should throw") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCoreSucceedsWhenAirQualityAndAlertsFail() async throws {
        let r = repo { req in
            if req.url!.host == "api.open-meteo.com" { return (DebugStubs.openMeteoJSON(), Fixture.response(req.url!)) }
            throw URLError(.timedOut)
        }
        let f = try await r.core(for: Fixture.la)
        XCTAssertEqual(f.daily.count, 8)
        let extras = await r.extras(for: Fixture.la)
        XCTAssertNil(extras.aqi)
        XCTAssertTrue(extras.alerts.isEmpty)
        XCTAssertFalse(extras.alertsLoaded)        // the caller keeps any alerts it already had
    }

    func testExtras() async {
        let r = repo { req in
            let host = req.url!.host!
            if host.contains("air-quality") { return (Data("{\"current\":{\"us_aqi\":88}}".utf8), Fixture.response(req.url!)) }
            if host == "api.weather.gov" {
                XCTAssertNotNil(req.value(forHTTPHeaderField: "User-Agent"))
                return (Data("{\"features\":[{\"id\":\"x\",\"properties\":{\"id\":\"x\",\"event\":\"Heat Advisory\",\"headline\":\"Hot\",\"severity\":\"Moderate\"}}]}".utf8), Fixture.response(req.url!))
            }
            return (DebugStubs.openMeteoJSON(), Fixture.response(req.url!))
        }
        let e = await r.extras(for: Fixture.la)
        XCTAssertEqual(e.aqi, 88)
        XCTAssertEqual(e.alerts.map(\.event), ["Heat Advisory"])
        XCTAssertTrue(e.alertsLoaded)
    }

    func testOutsideTheUSMeansNoAlertsNotAnError() async throws {
        let r = repo { req in (Data("{}".utf8), Fixture.response(req.url!, 404)) }
        let alerts = try await r.alerts(for: Place(name: "Paris", latitude: 48.86, longitude: 2.35))
        XCTAssertTrue(alerts.isEmpty)
    }
}

final class WidgetSnapshotTests: XCTestCase {
    func testRoundTrip() throws {
        let f = Fixture.forecast(Place(name: "Home", latitude: 32.71574, longitude: -117.16108, isCurrentLocation: true))
        let s = WidgetSnapshot(forecast: f, unit: .celsius, skin: .fog)
        let back = WidgetSnapshot.decode(try s.encoded())
        XCTAssertEqual(back, s)
        XCTAssertEqual(back?.tempUnit, .celsius)
        XCTAssertEqual(back?.skinValue, .fog)
        let g = back!.forecast
        XCTAssertEqual(g.place.name, "Home")
        XCTAssertTrue(g.place.isCurrentLocation)
        XCTAssertEqual(g.current.temperature, f.current.temperature)
        XCTAssertEqual(g.daily.count, 8)
        XCTAssertEqual(g.daily[1].high, f.daily[1].high)
        XCTAssertEqual(g.timeZone.identifier, f.timeZone.identifier)
    }

    func testOnlyCoarseLocationIsShared() throws {
        let f = Fixture.forecast(Place(name: "Home", latitude: 32.71574, longitude: -117.16108), now: Date(timeIntervalSince1970: 1_780_000_000))
        let s = WidgetSnapshot(forecast: f, unit: .fahrenheit, skin: .graphite)
        XCTAssertEqual(s.latitude, 32.7, accuracy: 0.0001)
        XCTAssertEqual(s.longitude, -117.2, accuracy: 0.0001)
        let text = String(data: try s.encoded(), encoding: .utf8)!
        XCTAssertFalse(text.contains("32.71"))
        XCTAssertFalse(text.contains("117.16"))
    }

    func testFreshnessWindows() {
        let now = Date()
        var s = WidgetSnapshot(forecast: Fixture.forecast(now: now), unit: .fahrenheit, skin: .graphite)
        XCTAssertTrue(s.isFresh(now: now.addingTimeInterval(2 * 3600)))
        XCTAssertFalse(s.isFresh(now: now.addingTimeInterval(4 * 3600)))
        XCTAssertTrue(s.isUsable(now: now.addingTimeInterval(40 * 3600)))
        XCTAssertFalse(s.isUsable(now: now.addingTimeInterval(50 * 3600)))
        s.version = 99
        XCTAssertNil(WidgetSnapshot.decode(try! s.encoded()))       // other versions are ignored
    }

    func testFileSaveAndLoad() {
        let url = Fixture.tempDir().appendingPathComponent(WidgetSnapshot.fileName)
        let s = WidgetSnapshot(forecast: Fixture.forecast(), unit: .fahrenheit, skin: .ember)
        XCTAssertTrue(s.save(to: url))
        XCTAssertEqual(WidgetSnapshot.load(from: url), s)
        XCTAssertNil(WidgetSnapshot.load(from: url.appendingPathExtension("missing")))
    }
}
