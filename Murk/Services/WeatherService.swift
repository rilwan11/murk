import Foundation

/// Live forecasts from Open-Meteo (free, no API key).
/// https://open-meteo.com — attribution is shown in the app's settings sheet.
struct WeatherService {
    enum ServiceError: LocalizedError {
        case badResponse
        case server(Int, String?)
        var errorDescription: String? {
            switch self {
            case .badResponse: return "The forecast came back incomplete. Tap to retry."
            case .server(let code, let reason): return "Forecast service error \(code)\(reason.map { ": \($0)" } ?? ""). Tap to retry."
            }
        }
    }
    private struct OMError: Decodable { let reason: String? }

    /// Fetches a fresh forecast. Times out quickly and retries with a lighter request,
    /// so a slow network never leaves the app spinning. Successful responses are cached.
    func forecast(for place: Place) async throws -> Forecast {
        var data: Data
        do {
            data = try await fetch(place, light: false, timeout: 12)
        } catch let e as URLError where [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains(e.code) {
            try Task.checkCancellation()
            data = try await fetch(place, light: true, timeout: 20)
        }
        var f = try parse(data, place: place, fetchedAt: Date())
        try? data.write(to: Self.cacheURL(place), options: .atomic)
        async let aqiTask = try? airQuality(for: place)
        async let alertTask = try? self.alerts(for: place)
        f.aqi = await aqiTask
        f.alerts = await alertTask ?? []
        return f
    }

    /// The last forecast saved for this place, shown instantly while a fresh one loads.
    static func cached(for place: Place) -> Forecast? {
        let url = cacheURL(place)
        guard let data = try? Data(contentsOf: url),
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              Date().timeIntervalSince(date) < 60 * 60 * 24 * 2 else { return nil }
        return try? WeatherService().parse(data, place: place, fetchedAt: date)
    }

    private static func cacheURL(_ place: Place) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let key = String(format: "%.3f_%.3f", place.latitude, place.longitude)
        return dir.appendingPathComponent("forecast_\(key).json")
    }

    private func fetch(_ place: Place, light: Bool, timeout: TimeInterval) async throws -> Data {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        var items: [URLQueryItem] = [
            .init(name: "latitude", value: String(format: "%.4f", place.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation,wind_speed_10m,wind_gusts_10m,wind_direction_10m,relative_humidity_2m,surface_pressure,visibility,uv_index"),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,is_day,wind_speed_10m,wind_direction_10m"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "8"),
        ]
        if !light {
            items += [.init(name: "minutely_15", value: "precipitation"), .init(name: "forecast_minutely_15", value: "12")]
        }
        c.queryItems = items
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = timeout
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ServiceError.server(code, (try? JSONDecoder().decode(OMError.self, from: data))?.reason) }
        return data
    }

    func parse(_ data: Data, place: Place, fetchedAt: Date) throws -> Forecast {
        let om = try JSONDecoder().decode(OMResponse.self, from: data)

        let tz = TimeZone(identifier: om.timezone) ?? TimeZone(secondsFromGMT: om.utc_offset_seconds) ?? .current
        let dt = DateFormatter(); dt.locale = Locale(identifier: "en_US_POSIX"); dt.timeZone = tz; dt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.timeZone = tz; df.dateFormat = "yyyy-MM-dd"

        guard let cur = om.current, let daily = om.daily else { throw ServiceError.badResponse }
        let current = CurrentWeather(
            temperature: cur.temperature_2m ?? daily.temperature_2m_max.first.flatMap { $0 } ?? 0,
            apparent: cur.apparent_temperature,
            code: cur.weather_code ?? 0,
            isDay: (cur.is_day ?? 1) == 1,
            windSpeed: cur.wind_speed_10m, windGust: cur.wind_gusts_10m, windDirection: cur.wind_direction_10m,
            precipitation: cur.precipitation,
            humidity: cur.relative_humidity_2m, pressure: cur.surface_pressure,
            visibility: cur.visibility, uvIndex: cur.uv_index)

        var days: [DailyWeather] = []
        for (i, ds) in daily.time.enumerated() {
            guard let date = df.date(from: ds) else { continue }
            func v<T>(_ a: [T?]?) -> T? { guard let a, i < a.count else { return nil }; return a[i] }
            days.append(DailyWeather(
                date: date,
                high: v(daily.temperature_2m_max) ?? 0,
                low: v(daily.temperature_2m_min) ?? 0,
                code: v(daily.weather_code) ?? 0,
                precipChance: Int((v(daily.precipitation_probability_max) ?? 0).rounded()),
                precipSum: v(daily.precipitation_sum) ?? 0,
                sunrise: v(daily.sunrise).flatMap { dt.date(from: $0) },
                sunset: v(daily.sunset).flatMap { dt.date(from: $0) },
                uvMax: v(daily.uv_index_max),
                windMax: v(daily.wind_speed_10m_max),
                gustMax: v(daily.wind_gusts_10m_max)))
        }

        var hours: [HourlyPoint] = []
        if let h = om.hourly {
            for (i, ts) in h.time.enumerated() {
                guard let t = dt.date(from: ts), i < h.temperature_2m.count, let temp = h.temperature_2m[i] else { continue }
                func hv<T>(_ a: [T?]?) -> T? { guard let a, i < a.count else { return nil }; return a[i] }
                let p = hv(h.precipitation_probability) ?? 0
                hours.append(HourlyPoint(time: t, temperature: temp, precipChance: Int(p.rounded()),
                                         code: hv(h.weather_code) ?? 0, isDay: (hv(h.is_day) ?? 1) == 1,
                                         windSpeed: hv(h.wind_speed_10m) ?? 0, windDirection: hv(h.wind_direction_10m) ?? 0,
                                         precip: hv(h.precipitation) ?? 0, apparent: hv(h.apparent_temperature)))
            }
        }

        var minutes: [MinutePoint] = []
        if let mq = om.minutely_15 {
            for (i, ts) in mq.time.enumerated() {
                guard let t = dt.date(from: ts) else { continue }
                let v = (mq.precipitation.flatMap { i < $0.count ? $0[i] : nil }) ?? 0
                minutes.append(MinutePoint(time: t, precip: v))
            }
        }

        return Forecast(place: place, current: current, daily: days, hourly: hours, minutely: minutes,
                        alerts: [], aqi: nil, timeZone: tz, fetchedAt: fetchedAt)
    }

    /// Active alerts from the US National Weather Service (empty outside the US).
    func alerts(for place: Place) async throws -> [WeatherAlert] {
        let lat = String(format: "%.4f", place.latitude), lon = String(format: "%.4f", place.longitude)
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(lat),\(lon)") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Murk weather app (github.com/rilwan11/murk)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        let r = try JSONDecoder().decode(NWSResponse.self, from: data)
        let iso = ISO8601DateFormatter()
        return r.features.compactMap { f in
            let p = f.properties
            guard let event = p.event else { return nil }
            return WeatherAlert(id: p.id ?? f.id ?? event, event: event, headline: p.headline ?? event,
                                severity: p.severity ?? "Unknown",
                                ends: (p.ends ?? p.expires).flatMap { iso.date(from: $0) })
        }
    }

    private func airQuality(for place: Place) async throws -> Int? {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "us_aqi"),
        ]
        var req = URLRequest(url: c.url!)
        req.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: req)
        let r = try JSONDecoder().decode(AQResponse.self, from: data)
        return r.current?.us_aqi.map { Int($0.rounded()) }
    }
}

// MARK: - Open-Meteo wire format

private struct OMResponse: Decodable {
    let utc_offset_seconds: Int
    let timezone: String
    let current: OMCurrent?
    let hourly: OMHourly?
    let daily: OMDaily?
    let minutely_15: OMMinutely?
}

private struct OMMinutely: Decodable {
    let time: [String]
    let precipitation: [Double?]?
}

private struct NWSResponse: Decodable {
    struct Feature: Decodable { let id: String?; let properties: Props }
    struct Props: Decodable {
        let id: String?; let event: String?; let headline: String?; let severity: String?
        let ends: String?; let expires: String?
    }
    let features: [Feature]
}

private struct OMCurrent: Decodable {
    let temperature_2m: Double?
    let apparent_temperature: Double?
    let weather_code: Int?
    let is_day: Int?
    let wind_speed_10m: Double?
    let wind_gusts_10m: Double?
    let wind_direction_10m: Double?
    let precipitation: Double?
    let relative_humidity_2m: Double?
    let surface_pressure: Double?
    let visibility: Double?
    let uv_index: Double?
}

private struct OMHourly: Decodable {
    let time: [String]
    let temperature_2m: [Double?]
    let apparent_temperature: [Double?]?
    let precipitation_probability: [Double?]?
    let precipitation: [Double?]?
    let weather_code: [Int?]?
    let is_day: [Int?]?
    let wind_speed_10m: [Double?]?
    let wind_direction_10m: [Double?]?
}

private struct OMDaily: Decodable {
    let time: [String]
    let weather_code: [Int?]?
    let temperature_2m_max: [Double?]
    let temperature_2m_min: [Double?]
    let precipitation_probability_max: [Double?]?
    let precipitation_sum: [Double?]?
    let sunrise: [String?]?
    let sunset: [String?]?
    let uv_index_max: [Double?]?
    let wind_speed_10m_max: [Double?]?
    let wind_gusts_10m_max: [Double?]?
}

private struct AQResponse: Decodable {
    struct Cur: Decodable { let us_aqi: Double? }
    let current: Cur?
}
