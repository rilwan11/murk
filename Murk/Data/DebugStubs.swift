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

        // Built piece by piece with explicit types, so the compiler never has to puzzle over one huge literal.
        func wave(_ base: Double) -> [Double] {
            hours.indices.map { (i: Int) -> Double in base + 6.0 * sin(Double(i % 24 - 9) / 24.0 * 2.0 * Double.pi) }
        }
        let hourTimes: [String] = hours.map { minute.string(from: $0) }
        let rainChance: [Double] = hours.indices.map { (i: Int) -> Double in wet(i) ? 80.0 : 5.0 }
        let rainAmount: [Double] = hours.indices.map { (i: Int) -> Double in wet(i) ? 1.2 : 0.0 }
        let codes: [Int] = hours.indices.map { (i: Int) -> Int in wet(i) ? 63 : 2 }
        let daylight: [Int] = hours.indices.map { (i: Int) -> Int in (7..<18).contains(i % 24) ? 1 : 0 }
        let uv: [Double] = hours.indices.map { (i: Int) -> Double in (10..<15).contains(i % 24) ? 5.0 : 0.0 }
        let steady: (Double) -> [Double] = { v in [Double](repeating: v, count: hours.count) }

        var current: [String: Any] = [:]
        current["temperature_2m"] = 19.4
        current["apparent_temperature"] = 18.8
        current["weather_code"] = 2
        current["is_day"] = 1
        current["precipitation"] = 0.0
        current["wind_speed_10m"] = 12.0
        current["wind_gusts_10m"] = 22.0
        current["wind_direction_10m"] = 270.0
        current["relative_humidity_2m"] = 60.0
        current["surface_pressure"] = 1015.0
        current["visibility"] = 16000.0
        current["uv_index"] = 4.0

        var hourly: [String: Any] = [:]
        hourly["time"] = hourTimes
        hourly["temperature_2m"] = wave(15.0)
        hourly["apparent_temperature"] = wave(14.5)
        hourly["precipitation_probability"] = rainChance
        hourly["precipitation"] = rainAmount
        hourly["weather_code"] = codes
        hourly["is_day"] = daylight
        hourly["wind_speed_10m"] = steady(12.0)
        hourly["wind_gusts_10m"] = steady(22.0)
        hourly["wind_direction_10m"] = steady(270.0)
        hourly["uv_index"] = uv

        let dayNames: [String] = days.map { day.string(from: $0) }
        let sunrises: [String] = days.map { minute.string(from: $0.addingTimeInterval(6.5 * 3600)) }
        let sunsets: [String] = days.map { minute.string(from: $0.addingTimeInterval(17 * 3600)) }
        let dayCodes: [Int] = [2, 61, 3, 2, 3, 2, 2, 61]
        let highs: [Double] = [21.0, 20.0, 21.0, 22.0, 20.0, 19.0, 20.0, 19.0]
        let lows: [Double] = [14.0, 13.0, 15.0, 15.0, 16.0, 13.0, 14.0, 14.0]
        let chances: [Double] = [5.0, 45.0, 20.0, 10.0, 20.0, 15.0, 15.0, 45.0]
        let sums: [Double] = [0.0, 2.1, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0]
        let uvMax: [Double] = [5.0, 4.0, 5.0, 6.0, 5.0, 4.0, 5.0, 4.0]
        let windMax: [Double] = [14.0, 22.0, 18.0, 12.0, 15.0, 16.0, 13.0, 20.0]
        let gustMax: [Double] = [25.0, 40.0, 30.0, 22.0, 26.0, 28.0, 24.0, 36.0]

        var daily: [String: Any] = [:]
        daily["time"] = dayNames
        daily["weather_code"] = dayCodes
        daily["temperature_2m_max"] = highs
        daily["temperature_2m_min"] = lows
        daily["precipitation_probability_max"] = chances
        daily["precipitation_sum"] = sums
        daily["sunrise"] = sunrises
        daily["sunset"] = sunsets
        daily["uv_index_max"] = uvMax
        daily["wind_speed_10m_max"] = windMax
        daily["wind_gusts_10m_max"] = gustMax

        var minutely: [String: Any] = [:]
        minutely["time"] = quarter.map { minute.string(from: $0) } as [String]
        minutely["precipitation"] = [Double](repeating: 0.0, count: quarter.count)

        var json: [String: Any] = [:]
        json["utc_offset_seconds"] = tz.secondsFromGMT(for: now)
        json["timezone"] = timeZone
        json["current"] = current
        json["hourly"] = hourly
        json["daily"] = daily
        json["minutely_15"] = minutely
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }
}
#endif
