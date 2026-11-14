import XCTest
@testable import Murk

enum Fixture {
    static let la = Place(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437)
    static let ny = Place(name: "New York", latitude: 40.7128, longitude: -74.0060)

    static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, zone: String = "America/Los_Angeles") -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    static func forecast(_ place: Place = la, now: Date = Date(), rainFromHour: Int? = nil, cached: Bool = false) -> Forecast {
        let data = DebugStubs.openMeteoJSON(now: now, rainFromHour: rainFromHour)
        return try! WeatherAPI.parseForecast(data, place: place, fetchedAt: now, isCached: cached)
    }

    static func defaults(_ name: String = UUID().uuidString) -> UserDefaults {
        let d = UserDefaults(suiteName: "murk.tests.\(name)")!
        d.removePersistentDomain(forName: "murk.tests.\(name)")
        return d
    }

    static func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("murk-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func response(_ url: URL, _ status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

/// A weather source whose answers and delays the test controls. Delays ignore cancellation,
/// like a request that is already on the wire.
final class FakeWeather: WeatherProviding, @unchecked Sendable {
    var delays: [String: Double] = [:]
    var failures: [String: WeatherError] = [:]
    var cachedPlaces: Set<String> = []
    var extrasResult = ForecastExtras(aqi: 42, alerts: [], alertsLoaded: true)
    private(set) var coreCalls = 0
    private let lock = NSLock()

    func cached(for place: Place) -> Forecast? {
        cachedPlaces.contains(place.name) ? Fixture.forecast(place, now: Date().addingTimeInterval(-7200), cached: true) : nil
    }

    func core(for place: Place) async throws -> Forecast {
        lock.lock(); coreCalls += 1; lock.unlock()
        let delay = delays[place.name] ?? 0.01
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { c.resume() }
        }
        if let e = failures[place.name] { throw e }
        return Fixture.forecast(place)
    }

    func extras(for place: Place) async -> ForecastExtras { extrasResult }
}

final class FakeLocation: LocationProviding {
    var isDenied = false
    var isAuthorized = true
    var result: Result<Place, Error> = .success(Place(name: "Here", latitude: 32.7, longitude: -117.2, isCurrentLocation: true))
    var delay = 0.01
    private(set) var calls = 0

    func currentPlace() async throws -> Place {
        calls += 1
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return try result.get()
    }
}

@MainActor
func makeState(weather: FakeWeather = FakeWeather(), location: FakeLocation = FakeLocation(),
               defaults: UserDefaults = Fixture.defaults(), places: [Place] = [Fixture.la, Fixture.ny]) -> AppState {
    defaults.set(try! JSONEncoder().encode(places), forKey: "places")
    let effects = AppState.Effects(syncWidget: { _, _, _, _ in }, notify: { _, _, _, _ in })
    return AppState(repository: weather, location: location, defaults: defaults, effects: effects)
}

func wait(_ seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}
