import Foundation
import SwiftUI
import WidgetKit

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
            syncWidget()
        } catch is CancellationError {
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't load the forecast."
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
    }

    private func savePlaces() {
        if let data = try? JSONEncoder().encode(places) { defaults.set(data, forKey: "places") }
    }

    // MARK: Derived

    /// Days from today onward in the forecast's own time zone.
    var days: [DailyWeather] { forecast?.daily ?? [] }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = forecast?.timeZone ?? .current
        return c
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
