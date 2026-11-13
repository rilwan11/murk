import Foundation

/// Settings the app shares with its widgets through an App Group.
/// If the App Group isn't set up (e.g. some free signing setups), widgets fall back to San Diego and °F.
enum SharedStore {
    static let appGroup = "group.com.example.murk"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static var place: Place {
        get {
            guard let d = defaults.data(forKey: "widget.place"), let p = try? JSONDecoder().decode(Place.self, from: d) else { return .sanDiego }
            return p
        }
        set { if let d = try? JSONEncoder().encode(newValue) { defaults.set(d, forKey: "widget.place") } }
    }

    static var unit: TempUnit {
        get { TempUnit(rawValue: defaults.string(forKey: "widget.unit") ?? "") ?? .fahrenheit }
        set { defaults.set(newValue.rawValue, forKey: "widget.unit") }
    }

    static var skin: Skin {
        get { Skin(rawValue: defaults.string(forKey: "widget.skin") ?? "") ?? .graphite }
        set { defaults.set(newValue.rawValue, forKey: "widget.skin") }
    }
}
