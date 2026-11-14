import Foundation
import CryptoKit

/// The small slice of the forecast the widgets need, written by the app into the App Group
/// so widgets can draw instantly, match the app, and keep working offline.
/// Coordinates are rounded to about 11 km (enough to place the sun in the sky) and nothing else about
/// where the user has been is stored.
struct WidgetSnapshot: Codable, Equatable {
    static let version = 1
    static let fileName = "widget-snapshot-v\(version).json"
    /// After this the widget may try one refresh of its own.
    static let freshFor: TimeInterval = 3 * 3600
    /// After this the snapshot is too old to show.
    static let usableFor: TimeInterval = 48 * 3600

    struct Day: Codable, Equatable {
        var date: Date
        var high: Double
        var low: Double
        var code: Int
        var precipChance: Int
    }

    var version = WidgetSnapshot.version
    var placeName: String
    var isCurrentLocation: Bool
    var latitude: Double
    var longitude: Double
    var timeZoneID: String
    var fetchedAt: Date
    var temperature: Double
    var apparent: Double?
    var code: Int
    var isDay: Bool
    var days: [Day]
    var unit: String
    var skin: String

    /// The next 24 hours and 3 hours of 15-minute rain, for the Rain, Air, Daylight and Moon widgets.
    /// Optional, so snapshots written by older versions still read.
    struct Hour: Codable, Equatable {
        var time: Date
        var temperature: Double
        var precipChance: Int
        var precip: Double
        var code: Int
        var isDay: Bool
        var windSpeed: Double
        var windDirection: Double
        var windGust: Double?
        var cloudCover: Double?
        var snowfall: Double?
    }
    struct Quarter: Codable, Equatable { var time: Date; var precip: Double }
    var hours: [Hour]? = nil
    var quarters: [Quarter]? = nil
    var windSpeed: Double? = nil
    var windDirection: Double? = nil
    var windGust: Double? = nil
    var precipitation: Double? = nil
    var aqi: Int? = nil

    init(forecast f: Forecast, unit: TempUnit, skin: Skin) {
        placeName = f.place.name
        isCurrentLocation = f.place.isCurrentLocation
        latitude = Coordinate.rounded(f.place.latitude, places: 1)
        longitude = Coordinate.rounded(f.place.longitude, places: 1)
        timeZoneID = f.timeZone.identifier
        // Whole seconds, so the value survives being written and read back unchanged.
        fetchedAt = Date(timeIntervalSince1970: f.fetchedAt.timeIntervalSince1970.rounded())
        temperature = f.current.temperature
        apparent = f.current.apparent
        code = f.current.code
        isDay = f.current.isDay
        days = f.daily.prefix(8).map { Day(date: $0.date, high: $0.high, low: $0.low, code: $0.code, precipChance: $0.precipChance) }
        self.unit = unit.rawValue
        self.skin = skin.rawValue
        func whole(_ d: Date) -> Date { Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded()) }
        let from = f.fetchedAt.addingTimeInterval(-3600)
        hours = f.hourly.filter { $0.time >= from }.prefix(30).map {
            Hour(time: whole($0.time), temperature: $0.temperature, precipChance: $0.precipChance, precip: $0.precip,
                 code: $0.code, isDay: $0.isDay, windSpeed: $0.windSpeed, windDirection: $0.windDirection,
                 windGust: $0.windGust, cloudCover: $0.cloudCover, snowfall: $0.snowfall)
        }
        quarters = f.minutely.filter { $0.time >= from }.prefix(14).map { Quarter(time: whole($0.time), precip: $0.precip) }
        windSpeed = f.current.windSpeed
        windDirection = f.current.windDirection
        windGust = f.current.windGust
        precipitation = f.current.precipitation
        aqi = f.air?.aqi ?? f.aqi
    }

    var tempUnit: TempUnit { TempUnit(rawValue: unit) ?? .fahrenheit }
    var skinValue: Skin { Skin(rawValue: skin) ?? .graphite }

    func isFresh(now: Date = Date()) -> Bool { now.timeIntervalSince(fetchedAt) < Self.freshFor }
    func isUsable(now: Date = Date()) -> Bool { now.timeIntervalSince(fetchedAt) < Self.usableFor }

    /// A forecast the widget views can draw from.
    var forecast: Forecast {
        Forecast(place: Place(name: placeName, latitude: latitude, longitude: longitude, isCurrentLocation: isCurrentLocation),
                 current: CurrentWeather(temperature: temperature, apparent: apparent, code: code, isDay: isDay,
                                         windSpeed: windSpeed, windGust: windGust, windDirection: windDirection,
                                         precipitation: precipitation),
                 daily: days.map { DailyWeather(date: $0.date, high: $0.high, low: $0.low, code: $0.code, precipChance: $0.precipChance,
                                                precipSum: 0, sunrise: nil, sunset: nil, uvMax: nil, windMax: nil, gustMax: nil) },
                 hourly: (hours ?? []).map {
                     HourlyPoint(time: $0.time, temperature: $0.temperature, precipChance: $0.precipChance, code: $0.code,
                                 isDay: $0.isDay, windSpeed: $0.windSpeed, windDirection: $0.windDirection, precip: $0.precip,
                                 windGust: $0.windGust, cloudCover: $0.cloudCover, snowfall: $0.snowfall)
                 },
                 minutely: (quarters ?? []).map { MinutePoint(time: $0.time, precip: $0.precip) },
                 aqi: aqi, timeZone: TimeZone(identifier: timeZoneID) ?? .current, fetchedAt: fetchedAt, isCached: true)
    }

    // MARK: Storage

    static var defaultURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?.appendingPathComponent(fileName)
    }

    /// Where the snapshot for one specific saved city lives (for widgets pinned to a city).
    /// The file name is a hash, so it says nothing about the place.
    static func fileName(placeID: String) -> String {
        let hash = SHA256.hash(data: Data("murk-widget|\(placeID)".utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
        return "widget-place-v\(version)-\(hash).json"
    }

    static func url(placeID: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?.appendingPathComponent(fileName(placeID: placeID))
    }

    func encoded() throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .secondsSince1970
        return try e.encode(self)
    }

    static func decode(_ data: Data) -> WidgetSnapshot? {
        let d = JSONDecoder(); d.dateDecodingStrategy = .secondsSince1970
        guard let s = try? d.decode(WidgetSnapshot.self, from: data), s.version == version else { return nil }
        return s
    }

    @discardableResult
    func save(to url: URL? = WidgetSnapshot.defaultURL) -> Bool {
        guard let url, let data = try? encoded() else { return false }
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }

    static func load(from url: URL? = WidgetSnapshot.defaultURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return decode(data)
    }
}
