import Foundation
import SwiftUI
import WidgetKit
import UIKit
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    // Places
    @Published var places: [Place] { didSet { savePlaces() } }
    /// nil = follow current location
    @Published var selectedID: String? { didSet { defaults.set(selectedID, forKey: "selectedID") } }
    @Published var currentPlace: Place?
    @Published var locationDenied = false

    // Weather
    @Published var forecast: Forecast?
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Settings
    @Published var unit: TempUnit { didSet { defaults.set(unit.rawValue, forKey: "unit"); syncWidget() } }
    @Published var skin: Skin { didSet { defaults.set(skin.rawValue, forKey: "skin"); syncWidget() } }
    @Published var minimal: Bool { didSet { defaults.set(minimal, forKey: "minimal") } }
    @Published var alerts: Bool { didSet { defaults.set(alerts, forKey: "alerts") } }
    @Published var autoSkin: Bool { didSet { defaults.set(autoSkin, forKey: "autoSkin"); if autoSkin { resolveAutoSkin() } } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound"); SoundEngine.shared.enabled = sound } }

    private let defaults = UserDefaults.standard
    private let location = LocationManager()
    private let service = WeatherService()
    private var loadTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        } else {
            places = [.sanDiego]
        }
        selectedID = defaults.string(forKey: "selectedID")
        unit = TempUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius)
        skin = Skin(rawValue: defaults.string(forKey: "skin") ?? "") ?? .graphite
        minimal = defaults.bool(forKey: "minimal")
        alerts = defaults.object(forKey: "alerts") as? Bool ?? true
        autoSkin = defaults.bool(forKey: "autoSkin")
        sound = defaults.object(forKey: "sound") as? Bool ?? true
        SoundEngine.shared.enabled = sound
    }

    /// Pick a skin from the weather: warm on sunny days, aurora at night, storm in rain, fog when grey.
    func resolveAutoSkin() {
        guard autoSkin, let c = forecast?.current else { return }
        let s: Skin
        switch c.code {
        case 95...99, 61...67, 80...82, 51...57: s = .storm
        case 71...77, 85, 86, 45, 48: s = .fog
        case 0, 1: s = c.isDay ? .ember : .aurora
        case 2: s = c.isDay ? .sunset : .aurora
        default: s = c.isDay ? .graphite : .aurora
        }
        if s != skin { skin = s }
    }

    // MARK: Cities

    /// nil = current location, then saved cities in order.
    var cityIDs: [String?] {
        var list: [String?] = locationDenied ? [] : [nil]
        list += places.map { Optional($0.id) }
        return list
    }

    var cityIndex: Int { cityIDs.firstIndex(where: { $0 == selectedID }) ?? 0 }

    func cycleCity(_ delta: Int) {
        let list = cityIDs
        guard list.count > 1 else { return }
        let next = list[(cityIndex + delta + list.count) % list.count]
        UISelectionFeedbackGenerator().selectionChanged()
        if let id = next, let p = places.first(where: { $0.id == id }) { select(p) } else { selectCurrentLocation() }
    }

    // MARK: Alerts → notifications

    private func notifyNewAlerts(_ list: [WeatherAlert], place: Place) {
        guard alerts, !list.isEmpty else { return }
        var seen = Set(defaults.stringArray(forKey: "seenAlerts") ?? [])
        let fresh = list.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { seen.insert($0.id) }
        defaults.set(Array(seen.suffix(200)), forKey: "seenAlerts")
        Self.postNotifications(fresh, place: place)
    }

    nonisolated static func postNotifications(_ list: [WeatherAlert], place: Place) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            for a in list {
                let c = UNMutableNotificationContent()
                c.title = "\(a.event) · \(place.name)"
                c.body = a.headline
                c.sound = .default
                center.add(UNNotificationRequest(identifier: a.id, content: c, trigger: nil))
            }
        }
    }

    var activePlace: Place? {
        if let id = selectedID, let p = places.first(where: { $0.id == id }) { return p }
        return currentPlace ?? places.first
    }

    var isFollowingLocation: Bool { selectedID == nil }

    // MARK: Actions

    func start() async {
        if selectedID == nil { await locate() }
        await load()
    }

    func locate() async {
        do {
            currentPlace = try await location.currentPlace()
            locationDenied = false
        } catch {
            // Falls back to the first saved city (see activePlace) while still following location.
            locationDenied = location.isDenied
        }
    }

    func load(force: Bool = false) async {
        guard let place = activePlace ?? places.first else { return }
        if !force, let f = forecast, f.place.id == place.id, Date().timeIntervalSince(f.fetchedAt) < 600 { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let f = try await service.forecast(for: place)
            guard (activePlace ?? places.first)?.id == place.id else { return } // user switched meanwhile
            forecast = f
            errorMessage = nil
            resolveAutoSkin()
            syncWidget()
            notifyNewAlerts(f.alerts, place: f.place)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            print("Murk forecast error:", error)
            errorMessage = Self.describe(error)
        }
    }

    func selectCurrentLocation() {
        selectedID = nil
        reload { await self.locate() }
    }

    func select(_ place: Place) {
        selectedID = place.id
        reload()
    }

    func add(_ place: Place) {
        if !places.contains(where: { $0.id == place.id }) { places.append(place) }
        select(place)
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.map { places[$0].id }
        places.remove(atOffsets: offsets)
        if let s = selectedID, removed.contains(s) { selectedID = nil; reload { await self.locate() } }
    }

    func refreshIfStale() {
        // Don't interrupt a load that's already running (e.g. right after the location prompt closes).
        if isLoading { return }
        loadTask?.cancel()
        loadTask = Task {
            if selectedID == nil { await locate() }
            await load()
        }
    }

    private func reload(before: (() async -> Void)? = nil) {
        loadTask?.cancel()
        loadTask = Task {
            await before?()
            await load(force: true)
        }
    }

    /// Hands the current place and look to the widgets and asks them to refresh.
    private func syncWidget() {
        if let p = forecast?.place ?? activePlace { SharedStore.place = p }
        SharedStore.unit = unit
        SharedStore.skin = skin
        WidgetCenter.shared.reloadAllTimelines()
        let s = skin
        DispatchQueue.main.async { SceneSnapshotter.renderIfNeeded(skin: s) }
    }

    /// A short, readable reason for a failed load, shown under the scene.
    static func describe(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription { return d }
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost: return "You're offline. Tap to retry."
            case .timedOut: return "The forecast took too long. Tap to retry."
            default: return "Network error (\(e.code.rawValue)). Tap to retry."
            }
        }
        if let e = error as? DecodingError {
            switch e {
            case .keyNotFound(let k, _): return "Forecast data missing “\(k.stringValue)”. Tap to retry."
            case .typeMismatch(_, let c), .valueNotFound(_, let c):
                return "Unexpected forecast data at \(c.codingPath.map(\.stringValue).joined(separator: ".")). Tap to retry."
            default: return "Couldn't read the forecast. Tap to retry."
            }
        }
        return "Couldn't load the forecast. Tap to retry."
    }

    func retry() { reload { if self.selectedID == nil { await self.locate() } } }

    private func savePlaces() {
        if let data = try? JSONEncoder().encode(places) { defaults.set(data, forKey: "places") }
    }

    // MARK: Derived

    /// The next 24 hours (starting with the current hour) for the scrubber.
    var upcomingHours: [HourlyPoint] {
        guard let f = forecast else { return [] }
        let now = Date().addingTimeInterval(-3600)
        return Array(f.hourly.filter { $0.time > now }.prefix(25))
    }

    /// Days from today onward in the forecast's own time zone.
    var days: [DailyWeather] { forecast?.daily ?? [] }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = forecast?.timeZone ?? .current
        return c
    }

    /// "RAIN IN 15 MIN" / "RAIN STOPS IN 30 MIN" from the 15-minute forecast, or nil.
    var nextHourRain: String? {
        guard let f = forecast else { return nil }
        let now = Date()
        let pts = f.minutely.filter { $0.time.addingTimeInterval(15 * 60) > now }.prefix(8)
        guard !pts.isEmpty else { return nil }
        let wet: (MinutePoint) -> Bool = { $0.precip >= 0.1 }
        let raining = (f.current.precipitation ?? 0) > 0.05 || wet(pts.first!)
        let word = f.current.condition.precip == .snow ? "SNOW" : "RAIN"
        func mins(_ p: MinutePoint) -> Int { max(5, Int((p.time.timeIntervalSince(now) / 60 / 5).rounded()) * 5) }
        if raining {
            if let dry = pts.first(where: { !wet($0) }) { return "\(word) STOPS IN \(mins(dry)) MIN" }
            return nil
        }
        if let first = pts.first(where: wet) { return "\(word) IN \(mins(first)) MIN" }
        return nil
    }

    func dayLabel(_ d: DailyWeather, index: Int) -> String {
        if index == 0 { return "TODAY" }
        let f = DateFormatter(); f.timeZone = forecast?.timeZone; f.dateFormat = "EEE"
        return f.string(from: d.date).uppercased()
    }

    func time(_ date: Date?) -> String {
        guard let date else { return "--" }
        let f = DateFormatter(); f.timeZone = forecast?.timeZone; f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// A short heads-up for the pill above the scene, or nil.
    var headsUp: String? {
        guard alerts, let f = forecast else { return nil }
        if let a = f.alerts.first { return a.event.uppercased() }
        if let r = nextHourRain { return r }
        if f.current.condition.precip == .rain { return "RAIN NOW" }
        if f.current.condition.precip == .snow { return "SNOW NOW" }
        for (i, d) in f.daily.prefix(3).enumerated() where d.precipChance >= 40 {
            let when = i == 0 ? "TODAY" : i == 1 ? "TOMORROW" : dayLabel(d, index: i)
            return "\(d.precipChance)% \(d.condition.precip == .snow ? "SNOW" : "RAIN") \(when)"
        }
        if let uv = f.daily.first?.uvMax, uv >= 8 { return "UV \(Int(uv.rounded())) TODAY" }
        if let g = f.current.windGust, g >= 50 { return "GUSTY WINDS" }
        return nil
    }
}
