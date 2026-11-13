import Foundation

// MARK: - Places

struct Place: Codable, Hashable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double
    var isCurrentLocation: Bool = false

    var id: String {
        isCurrentLocation ? "current" : "\(name)|\(String(format: "%.3f", latitude))|\(String(format: "%.3f", longitude))"
    }

    static let sanDiego = Place(name: "San Diego", latitude: 32.7157, longitude: -117.1611)
}

// MARK: - Units

enum TempUnit: String, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: String { rawValue }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }

    /// Converts an internal Celsius value for display.
    func temp(_ c: Double) -> Int {
        self == .fahrenheit ? Int((c * 9 / 5 + 32).rounded()) : Int(c.rounded())
    }
    /// Internal wind is km/h.
    func wind(_ kmh: Double) -> String {
        self == .fahrenheit ? "\(Int((kmh * 0.621371).rounded())) MPH" : "\(Int(kmh.rounded())) KM/H"
    }
    func windValue(_ kmh: Double) -> Double { self == .fahrenheit ? kmh * 0.621371 : kmh }
    var windLabel: String { self == .fahrenheit ? "MPH" : "KM/H" }
    /// Internal visibility is meters.
    func visibility(_ m: Double) -> String {
        self == .fahrenheit ? String(format: "%.0f MI", m / 1609.34) : String(format: "%.0f KM", m / 1000)
    }
    /// Internal pressure is hPa.
    func pressure(_ hPa: Double) -> String {
        self == .fahrenheit ? String(format: "%.2f INHG", hPa * 0.02953) : "\(Int(hPa.rounded())) HPA"
    }
    /// Internal precipitation is mm.
    func precip(_ mm: Double) -> String {
        self == .fahrenheit ? String(format: "%.2f IN", mm / 25.4) : String(format: "%.1f MM", mm)
    }
}

// MARK: - Conditions (WMO weather codes)

enum Precip { case none, rain, snow }

struct Condition {
    let code: Int
    let isDay: Bool

    var title: String {
        switch code {
        case 0: return isDay ? "Sunny" : "Clear"
        case 1: return isDay ? "Mostly Sunny" : "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Mostly Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 80: return "Light Rain"
        case 63, 81: return "Rain"
        case 65, 82: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 85: return "Light Snow"
        case 73, 75, 77, 86: return "Snow"
        case 95: return "Thunderstorms"
        case 96, 99: return "Hail Storms"
        default: return "—"
        }
    }

    /// 0…1, drives how many cloud puffs the 3D scene builds.
    var cloudCover: Double {
        switch code {
        case 0: return 0.08
        case 1: return 0.3
        case 2: return 0.55
        case 3: return 0.85
        case 45, 48: return 0.75
        case 95...99: return 1
        default: return 0.9
        }
    }

    var precip: Precip {
        switch code {
        case 51...67, 80...82, 95...99: return .rain
        case 71...77, 85, 86: return .snow
        default: return .none
        }
    }

    /// 0…1 intensity for particles.
    var intensity: Double {
        switch code {
        case 51, 56, 61, 71, 80, 85: return 0.35
        case 53, 63, 73, 81: return 0.65
        case 55, 57, 65, 66, 67, 75, 77, 82, 86, 95, 96, 99: return 1
        default: return 0
        }
    }

    var symbol: String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Forecast (all values metric internally)

struct CurrentWeather {
    var temperature: Double
    var apparent: Double?
    var code: Int
    var isDay: Bool
    var windSpeed: Double?
    var windGust: Double?
    var windDirection: Double?
    var precipitation: Double?
    var humidity: Double?
    var pressure: Double?
    var visibility: Double?
    var uvIndex: Double?

    var condition: Condition { Condition(code: code, isDay: isDay) }
}

struct DailyWeather: Identifiable {
    var id: Date { date }
    var date: Date
    var high: Double
    var low: Double
    var code: Int
    var precipChance: Int
    var precipSum: Double
    var sunrise: Date?
    var sunset: Date?
    var uvMax: Double?
    var windMax: Double?
    var gustMax: Double?

    var condition: Condition { Condition(code: code, isDay: true) }
}

struct HourlyPoint: Identifiable {
    var id: Date { time }
    var time: Date
    var temperature: Double
    var precipChance: Int
    var code: Int = 0
    var isDay: Bool = true
    var windSpeed: Double = 0
    var windDirection: Double = 0
    var precip: Double = 0          // mm in the hour
    var apparent: Double?

    var condition: Condition { Condition(code: code, isDay: isDay) }
}

/// 15-minute precipitation, used for "rain starts in 12 min".
struct MinutePoint {
    var time: Date
    var precip: Double              // mm in the 15 minutes
}

/// An official weather alert (US: National Weather Service).
struct WeatherAlert: Identifiable, Hashable {
    var id: String
    var event: String
    var headline: String
    var severity: String
    var ends: Date?
}

struct Forecast {
    var place: Place
    var current: CurrentWeather
    var daily: [DailyWeather]
    var hourly: [HourlyPoint]
    var minutely: [MinutePoint] = []
    var alerts: [WeatherAlert] = []
    var aqi: Int?
    var timeZone: TimeZone
    var fetchedAt: Date
}

// MARK: - Helpers

extension Double {
    var compassDirection: String {
        let dirs = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let i = Int((self / 22.5).rounded()) % 16
        return dirs[(i + 16) % 16]
    }
}

func aqiLabel(_ v: Int) -> String {
    switch v {
    case ..<51: return "GOOD"
    case ..<101: return "MODERATE"
    case ..<151: return "SENSITIVE"
    case ..<201: return "UNHEALTHY"
    case ..<301: return "VERY UNHEALTHY"
    default: return "HAZARDOUS"
    }
}
