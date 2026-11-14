import Foundation
import WidgetKit

/// What the watch app and its complications share: the place, and the last forecast as it came from the server.
enum WatchStore {
    static let appGroup = "group.com.rilwan11.murk"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var place: Place {
        get {
            guard let d = defaults.data(forKey: "watch.place"), let p = try? JSONDecoder().decode(Place.self, from: d) else { return .sanDiego }
            return p
        }
        set { if let d = try? JSONEncoder().encode(newValue) { defaults.set(d, forKey: "watch.place") } }
    }

    static var unit: TempUnit {
        Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    /// The last forecast saved by either the app or a complication.
    static func cached() -> Forecast? {
        guard let data = defaults.data(forKey: "watch.forecast"),
              let at = defaults.object(forKey: "watch.fetchedAt") as? Date else { return nil }
        let p = place
        return try? WeatherAPI.parseForecast(data, place: p, fetchedAt: at, isCached: true)
    }

    /// Downloads a fresh forecast for the place and keeps it for the complications.
    static func fetch(_ p: Place) async throws -> Forecast {
        var req = URLRequest(url: WeatherAPI.forecastURL(p), timeoutInterval: 20)
        req.setValue("Murk-Watch", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let now = Date()
        let f = try WeatherAPI.parseForecast(data, place: p, fetchedAt: now)
        let d = defaults
        place = p
        d.set(data, forKey: "watch.forecast")
        d.set(now, forKey: "watch.fetchedAt")
        return f
    }

    /// A forecast no older than `maxAge`, fetching one if needed. Falls back to the cache when offline.
    static func current(maxAge: TimeInterval = 30 * 60) async -> Forecast? {
        if let c = cached(), Date().timeIntervalSince(c.fetchedAt) < maxAge { return c }
        return (try? await fetch(place)) ?? cached()
    }
}

/// Plain colors for the watch, where the app's skins don't apply.
enum WatchInk {
    static let rain = 0x6FB7FF
    static let moon = 0xE8E4D8
}
