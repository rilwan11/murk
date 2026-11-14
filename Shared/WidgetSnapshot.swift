import Foundation

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
    }

    var tempUnit: TempUnit { TempUnit(rawValue: unit) ?? .fahrenheit }
    var skinValue: Skin { Skin(rawValue: skin) ?? .graphite }

    func isFresh(now: Date = Date()) -> Bool { now.timeIntervalSince(fetchedAt) < Self.freshFor }
    func isUsable(now: Date = Date()) -> Bool { now.timeIntervalSince(fetchedAt) < Self.usableFor }

    /// A forecast the widget views can draw from.
    var forecast: Forecast {
        Forecast(place: Place(name: placeName, latitude: latitude, longitude: longitude, isCurrentLocation: isCurrentLocation),
                 current: CurrentWeather(temperature: temperature, apparent: apparent, code: code, isDay: isDay),
                 daily: days.map { DailyWeather(date: $0.date, high: $0.high, low: $0.low, code: $0.code, precipChance: $0.precipChance,
                                                precipSum: 0, sunrise: nil, sunset: nil, uvMax: nil, windMax: nil, gustMax: nil) },
                 hourly: [], aqi: nil, timeZone: TimeZone(identifier: timeZoneID) ?? .current, fetchedAt: fetchedAt, isCached: true)
    }

    // MARK: Storage

    static var defaultURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?.appendingPathComponent(fileName)
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
