import Foundation

/// Live forecasts from Open-Meteo (free, no API key).
/// https://open-meteo.com — attribution is shown in the app's settings sheet.
struct WeatherService {
    enum ServiceError: LocalizedError {
        case badResponse
        var errorDescription: String? { "Couldn't load the forecast. Check your connection and try again." }
    }

    func forecast(for place: Place) async throws -> Forecast {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,wind_gusts_10m,wind_direction_10m,relative_humidity_2m,surface_pressure,visibility,uv_index"),
            .init(name: "hourly", value: "temperature_2m,precipitation_probability"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset,uv_index_max,wind_speed_10m_max,wind_gusts_10m_max"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "8"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: c.url!)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.badResponse }
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
                let p = (h.precipitation_probability.flatMap { i < $0.count ? $0[i] : nil }) ?? 0
                hours.append(HourlyPoint(time: t, temperature: temp, precipChance: Int(p.rounded())))
            }
        }

        let aqi = try? await airQuality(for: place)
        return Forecast(place: place, current: current, daily: days, hourly: hours, aqi: aqi, timeZone: tz, fetchedAt: Date())
    }

    private func airQuality(for place: Place) async throws -> Int? {
        var c = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        c.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "us_aqi"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
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
}

private struct OMCurrent: Decodable {
    let temperature_2m: Double?
    let apparent_temperature: Double?
    let weather_code: Int?
    let is_day: Int?
    let wind_speed_10m: Double?
    let wind_gusts_10m: Double?
    let wind_direction_10m: Double?
    let relative_humidity_2m: Double?
    let surface_pressure: Double?
    let visibility: Double?
    let uv_index: Double?
}

private struct OMHourly: Decodable {
    let time: [String]
    let temperature_2m: [Double?]
    let precipitation_probability: [Double?]?
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
