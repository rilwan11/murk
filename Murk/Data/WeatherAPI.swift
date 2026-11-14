import Foundation

/// Machine formatting for coordinates: always a decimal point, whatever the phone's region.
enum Coordinate {
    static let posix = Locale(identifier: "en_US_POSIX")

    /// 2 places ≈ 1 km, which is finer than any forecast grid; 1 place ≈ 11 km for approximate mode.
    static func string(_ value: Double, places: Int = 2) -> String {
        String(format: "%.\(max(0, places))f", locale: posix, value)
    }

    static func rounded(_ value: Double, places: Int) -> Double {
        let k = pow(10, Double(max(0, places)))
        return (value * k).rounded() / k
    }
}

/// Where forecasts come from. Swappable, so the data source can change without touching the app.
struct ProviderConfig: Equatable {
    var name: String
    var forecastBase: String
    var airQualityBase: String
    var alertsBase: String
    /// Only the commercial plan uses a key; the free endpoint needs none.
    var apiKey: String?
    var attributionURL: String

    var isCommercial: Bool { !(apiKey ?? "").isEmpty }

    static let openMeteoFree = ProviderConfig(
        name: "Open-Meteo",
        forecastBase: "https://api.open-meteo.com/v1/forecast",
        airQualityBase: "https://air-quality-api.open-meteo.com/v1/air-quality",
        alertsBase: "https://api.weather.gov/alerts/active",
        apiKey: nil,
        attributionURL: "https://open-meteo.com")

    /// Open-Meteo's paid plan: same API on customer hosts, with a key.
    static func openMeteoCommercial(apiKey: String) -> ProviderConfig {
        ProviderConfig(
            name: "Open-Meteo",
            forecastBase: "https://customer-api.open-meteo.com/v1/forecast",
            airQualityBase: "https://customer-air-quality-api.open-meteo.com/v1/air-quality",
            alertsBase: "https://api.weather.gov/alerts/active",
            apiKey: apiKey,
            attributionURL: "https://open-meteo.com")
    }

    /// Uses the commercial plan when a key is supplied at build time (Info.plist `MurkWeatherAPIKey`).
    static var current: ProviderConfig {
        let key = (Bundle.main.object(forInfoDictionaryKey: "MurkWeatherAPIKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty || key.hasPrefix("$(") ? .openMeteoFree : .openMeteoCommercial(apiKey: key)
    }
}

/// Request building and response parsing. Pure functions, so they can be tested without a network.
enum WeatherAPI {
    enum ParseError: Error { case incomplete }

    static func forecastURL(_ place: Place, light: Bool = false, places: Int = 2, config: ProviderConfig = .current) -> URL {
        var c = URLComponents(string: config.forecastBase)!
        var items: [URLQueryItem] = [
            .init(name: "latitude", value: Coordinate.string(place.latitude, places: places)),
            .init(name: "longitude", value: Coordinate.string(place.longitude, places: places)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation,wind_speed_10m,wind_gusts_10m,wind_direction_10m,relative_humidity_2m,surface_pressure,visibility,uv_index"),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,precipitation_probability,precipitation,weather_code,is_day,wind_speed_10m,wind_gusts_10m,wind_direction_10m,uv_index"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "8"),
        ]
        if !light {
            items += [.init(name: "minutely_15", value: "precipitation"), .init(name: "forecast_minutely_15", value: "12")]
        }
        if let key = config.apiKey, !key.isEmpty { items.append(.init(name: "apikey", value: key)) }
        c.queryItems = items
        return c.url!
    }

    static func airQualityURL(_ place: Place, places: Int = 2, config: ProviderConfig = .current) -> URL {
        var c = URLComponents(string: config.airQualityBase)!
        var items: [URLQueryItem] = [
            .init(name: "latitude", value: Coordinate.string(place.latitude, places: places)),
            .init(name: "longitude", value: Coordinate.string(place.longitude, places: places)),
            .init(name: "current", value: "us_aqi"),
        ]
        if let key = config.apiKey, !key.isEmpty { items.append(.init(name: "apikey", value: key)) }
        c.queryItems = items
        return c.url!
    }

    static func alertsURL(_ place: Place, places: Int = 2, config: ProviderConfig = .current) -> URL {
        var c = URLComponents(string: config.alertsBase)!
        c.queryItems = [.init(name: "point", value: "\(Coordinate.string(place.latitude, places: places)),\(Coordinate.string(place.longitude, places: places))")]
        return c.url!
    }

    // MARK: Parsing

    static func parseForecast(_ data: Data, place: Place, fetchedAt: Date, isCached: Bool = false) throws -> Forecast {
        let om = try JSONDecoder().decode(OMResponse.self, from: data)

        let tz = TimeZone(identifier: om.timezone) ?? TimeZone(secondsFromGMT: om.utc_offset_seconds) ?? .current
        let dt = DateFormatter(); dt.locale = Coordinate.posix; dt.calendar = Calendar(identifier: .gregorian); dt.timeZone = tz; dt.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let df = DateFormatter(); df.locale = Coordinate.posix; df.calendar = Calendar(identifier: .gregorian); df.timeZone = tz; df.dateFormat = "yyyy-MM-dd"

        guard let cur = om.current, let daily = om.daily else { throw ParseError.incomplete }
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
                                         precip: hv(h.precipitation) ?? 0, apparent: hv(h.apparent_temperature),
                                         windGust: hv(h.wind_gusts_10m), uvIndex: hv(h.uv_index)))
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
                        alerts: [], aqi: nil, timeZone: tz, fetchedAt: fetchedAt, isCached: isCached)
    }

    /// Active alerts in NWS GeoJSON. Alerts that have already ended are dropped.
    static func parseAlerts(_ data: Data, now: Date = Date()) throws -> [WeatherAlert] {
        let r = try JSONDecoder().decode(NWSResponse.self, from: data)
        let iso = ISO8601DateFormatter()
        let isoFraction = ISO8601DateFormatter(); isoFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) ?? isoFraction.date(from: $0) } }
        return r.features.compactMap { f in
            let p = f.properties
            guard let event = p.event else { return nil }
            let ends = date(p.ends) ?? date(p.expires)
            if let ends, ends < now { return nil }
            return WeatherAlert(id: p.id ?? f.id ?? event, event: event, headline: p.headline ?? event,
                                severity: p.severity ?? "Unknown", ends: ends,
                                detail: p.description, instruction: p.instruction)
        }
    }

    static func parseAQI(_ data: Data) throws -> Int? {
        try JSONDecoder().decode(AQResponse.self, from: data).current?.us_aqi.map { Int($0.rounded()) }
    }

    static func errorReason(_ data: Data) -> String? {
        (try? JSONDecoder().decode(OMError.self, from: data))?.reason
    }
}

// MARK: - Wire formats

private struct OMError: Decodable { let reason: String? }

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
        let ends: String?; let expires: String?; let description: String?; let instruction: String?
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
    let wind_gusts_10m: [Double?]?
    let wind_direction_10m: [Double?]?
    let uv_index: [Double?]?
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
