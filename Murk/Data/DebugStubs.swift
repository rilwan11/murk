#if DEBUG
import Foundation

/// Canned data for tests and UI smoke tests. Compiled into debug builds only.
enum DebugStubs {
    /// `-MurkStub online|offline|provider-down` on the command line replaces the network.
    static var mode: String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-MurkStub"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    static func repository() -> WeatherProviding? {
        guard let mode else { return nil }
        var repo = WeatherRepository()
        repo.fetch = { req in
            let url = req.url!
            switch mode {
            case "offline": throw URLError(.notConnectedToInternet)
            case "provider-down":
                return (Data("{\"reason\":\"down\"}".utf8), HTTPURLResponse(url: url, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            default:
                let body: Data
                if url.host?.contains("air-quality") == true { body = Data("{\"current\":{\"us_aqi\":42}}".utf8) }
                else if url.host?.contains("weather.gov") == true { body = Data("{\"features\":[]}".utf8) }
                else { body = openMeteoJSON() }
                return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
        }
        return repo
    }

    /// A complete Open-Meteo response: 8 days, 192 hours, 12 quarter-hours, starting today in the given zone.
    static func openMeteoJSON(now: Date = Date(), timeZone: String = "America/Los_Angeles", rainFromHour: Int? = nil) -> Data {
        let tz = TimeZone(identifier: timeZone) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let start = cal.startOfDay(for: now)
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.calendar = cal; day.timeZone = tz; day.dateFormat = "yyyy-MM-dd"
        let minute = DateFormatter(); minute.locale = Locale(identifier: "en_US_POSIX"); minute.calendar = cal; minute.timeZone = tz; minute.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let days = (0..<8).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let hours = (0..<192).map { start.addingTimeInterval(Double($0) * 3600) }
        let quarter = (0..<12).map { now.addingTimeInterval(Double($0) * 900) }
        func wet(_ i: Int) -> Bool { rainFromHour.map { i >= $0 && i < $0 + 6 } ?? false }

        let json: [String: Any] = [
            "utc_offset_seconds": tz.secondsFromGMT(for: now),
            "timezone": timeZone,
            "current": ["temperature_2m": 19.4, "apparent_temperature": 18.8, "weather_code": 2, "is_day": 1, "precipitation": 0.0,
                        "wind_speed_10m": 12.0, "wind_gusts_10m": 22.0, "wind_direction_10m": 270.0, "relative_humidity_2m": 60.0,
                        "surface_pressure": 1015.0, "visibility": 16000.0, "uv_index": 4.0],
            "hourly": [
                "time": hours.map { minute.string(from: $0) },
                "temperature_2m": hours.indices.map { 15.0 + 6.0 * sin(Double($0 % 24 - 9) / 24 * 2 * .pi) },
                "apparent_temperature": hours.indices.map { 14.5 + 6.0 * sin(Double($0 % 24 - 9) / 24 * 2 * .pi) },
                "precipitation_probability": hours.indices.map { wet($0) ? 80.0 : 5.0 },
                "precipitation": hours.indices.map { wet($0) ? 1.2 : 0.0 },
                "weather_code": hours.indices.map { wet($0) ? 63 : 2 },
                "is_day": hours.indices.map { (7..<18).contains($0 % 24) ? 1 : 0 },
                "wind_speed_10m": hours.indices.map { _ in 12.0 },
                "wind_gusts_10m": hours.indices.map { _ in 22.0 },
                "wind_direction_10m": hours.indices.map { _ in 270.0 },
                "uv_index": hours.indices.map { (10..<15).contains($0 % 24) ? 5.0 : 0.0 },
            ],
            "daily": [
                "time": days.map { day.string(from: $0) },
                "weather_code": [2, 61, 3, 2, 3, 2, 2, 61],
                "temperature_2m_max": [21.0, 20.0, 21.0, 22.0, 20.0, 19.0, 20.0, 19.0],
                "temperature_2m_min": [14.0, 13.0, 15.0, 15.0, 16.0, 13.0, 14.0, 14.0],
                "precipitation_probability_max": [5.0, 45.0, 20.0, 10.0, 20.0, 15.0, 15.0, 45.0],
                "precipitation_sum": [0.0, 2.1, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0],
                "sunrise": days.map { minute.string(from: $0.addingTimeInterval(6.5 * 3600)) },
                "sunset": days.map { minute.string(from: $0.addingTimeInterval(17 * 3600)) },
                "uv_index_max": [5.0, 4.0, 5.0, 6.0, 5.0, 4.0, 5.0, 4.0],
                "wind_speed_10m_max": [14.0, 22.0, 18.0, 12.0, 15.0, 16.0, 13.0, 20.0],
                "wind_gusts_10m_max": [25.0, 40.0, 30.0, 22.0, 26.0, 28.0, 24.0, 36.0],
            ],
            "minutely_15": ["time": quarter.map { minute.string(from: $0) }, "precipitation": quarter.map { _ in 0.0 }],
        ]
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}
#endif
