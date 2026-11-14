import Foundation

/// Settings the app shares with its widgets through an App Group.
/// If the App Group isn't set up (e.g. some free signing setups), widgets fall back to San Diego and °F.
enum SharedStore {
    static let appGroup = "group.com.rilwan11.murk"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var place: Place {
        get {
            guard let d = defaults.data(forKey: "widget.place"), let p = try? JSONDecoder().decode(Place.self, from: d) else { return .sanDiego }
            return p
        }
        set {
            // Widgets only need the neighborhood, so the shared copy is rounded to about 1 km.
            var p = newValue
            p.latitude = Coordinate.rounded(p.latitude, places: 2)
            p.longitude = Coordinate.rounded(p.longitude, places: 2)
            if let d = try? JSONEncoder().encode(p) { defaults.set(d, forKey: "widget.place") }
        }
    }

    static var unit: TempUnit {
        get { TempUnit(rawValue: defaults.string(forKey: "widget.unit") ?? "") ?? .fahrenheit }
        set { defaults.set(newValue.rawValue, forKey: "widget.unit") }
    }

    static var skin: Skin {
        get { Skin(rawValue: defaults.string(forKey: "widget.skin") ?? "") ?? .graphite }
        set { defaults.set(newValue.rawValue, forKey: "widget.skin") }
    }

    /// Round coordinates to about 11 km before sending them to weather providers.
    static var approximateLocation: Bool {
        get { defaults.bool(forKey: "privacy.approximate") }
        set { defaults.set(newValue, forKey: "privacy.approximate") }
    }

    /// Whether Murk Pro is active, so widgets can honor Pro choices without talking to the App Store.
    static var isPro: Bool {
        get { defaults.bool(forKey: "pro.active") }
        set { defaults.set(newValue, forKey: "pro.active") }
    }

    /// The saved cities a widget can be pointed at (rounded to about 1 km, like every shared coordinate).
    static var places: [SharedPlace] {
        get {
            guard let d = defaults.data(forKey: "widget.places") else { return [] }
            return (try? JSONDecoder().decode([SharedPlace].self, from: d)) ?? []
        }
        set { if let d = try? JSONEncoder().encode(newValue) { defaults.set(d, forKey: "widget.places") } }
    }
}

/// A saved city as widgets see it.
struct SharedPlace: Codable, Equatable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double

    init(_ p: Place) {
        id = p.id; name = p.name
        latitude = Coordinate.rounded(p.latitude, places: 2)
        longitude = Coordinate.rounded(p.longitude, places: 2)
    }

    var place: Place { Place(name: name, latitude: latitude, longitude: longitude) }
}

/// How a widget is dressed.
enum WidgetLook: String, CaseIterable {
    case sky, skin, midnight
    /// The live sky is free; the others are part of Murk Pro.
    var isPremium: Bool { self != .sky }
}

/// Turns what someone picked while editing a widget into what the widget may show.
/// Without Murk Pro a widget follows the app and wears the live sky, whatever was picked.
enum WidgetChoice {
    static func resolve(placeID: String?, look: WidgetLook, isPro: Bool, places: [SharedPlace]) -> (place: SharedPlace?, look: WidgetLook) {
        guard isPro else { return (nil, .sky) }
        return (placeID.flatMap { id in places.first { $0.id == id } }, look)
    }
}
