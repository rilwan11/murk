import Foundation
import SwiftUI
import WidgetKit
import UIKit
import UserNotifications

/// Why the paywall is being shown (always a moment where Pro adds something the user just asked for).
enum PaywallReason: String, Identifiable {
    case city, skin, alerts, general
    var id: String { rawValue }
}

/// Presentation state and user actions. Data access lives in `WeatherRepository`.
@MainActor
final class AppState: ObservableObject {
    /// Things that reach outside the app, replaceable in tests.
    struct Effects {
        var syncWidget: (Forecast?, Place?, TempUnit, Skin) -> Void = LiveEffects.syncWidget
        var notify: (Forecast, NotificationRules, TempUnit, Bool) -> Void = LiveEffects.notify
    }

    // Places
    @Published var places: [Place] { didSet { savePlaces() } }
    /// nil = follow current location
    @Published var selectedID: String? { didSet { defaults.set(selectedID, forKey: "selectedID") } }
    @Published var currentPlace: Place?
    @Published var locationDenied = false
    /// The user chose "Use Current Location". Location is never requested before that.
    @Published var useLocation: Bool { didSet { defaults.set(useLocation, forKey: "useLocation") } }
    /// Why the current location isn't being shown, if it isn't.
    @Published var locationProblem: LocationError?

    // Weather
    @Published var forecast: Forecast?
    @Published var isLoading = false
    @Published var failure: WeatherError?

    // Navigation
    @Published var route: DeepLink?
    @Published var paywall: PaywallReason?

    // Settings
    @Published var unit: TempUnit { didSet { defaults.set(unit.rawValue, forKey: "unit"); syncWidget() } }
    @Published var skin: Skin { didSet { defaults.set(skin.rawValue, forKey: "skin"); syncWidget() } }
    @Published var minimal: Bool { didSet { defaults.set(minimal, forKey: "minimal") } }
    /// The heads-up pill above the scene.
    @Published var alerts: Bool { didSet { defaults.set(alerts, forKey: "alerts") } }
    @Published var autoSkin: Bool { didSet { defaults.set(autoSkin, forKey: "autoSkin"); if autoSkin { resolveAutoSkin() } } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound"); SoundEngine.shared.enabled = sound } }
    @Published var approximateLocation: Bool { didSet { SharedStore.approximateLocation = approximateLocation } }
    @Published var rules: NotificationRules { didSet { rules.save(defaults) } }
    @Published private(set) var isPro: Bool

    private let defaults: UserDefaults
    private let location: LocationProviding
    private let repository: WeatherProviding
    private let effects: Effects
    private var loadTask: Task<Void, Never>?
    /// Only the newest request may touch the screen.
    private var generation = 0
    private var loadInFlight = false

    init(repository: WeatherProviding = WeatherRepository.live,
         location: LocationProviding = LocationManager(),
         defaults: UserDefaults = .standard,
         effects: Effects = Effects()) {
        self.repository = repository
        self.location = location
        self.defaults = defaults
        self.effects = effects
        if let data = defaults.data(forKey: "places"), let saved = try? JSONDecoder().decode([Place].self, from: data) {
            places = saved
        } else {
            places = [.sanDiego]
        }
        selectedID = defaults.string(forKey: "selectedID")
        // People who already allowed location keep following it; nobody else is asked until they choose to.
        useLocation = defaults.object(forKey: "useLocation") as? Bool ?? location.isAuthorized
        unit = TempUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? (Locale.current.measurementSystem == .us ? .fahrenheit : .celsius)
        skin = Skin(rawValue: defaults.string(forKey: "skin") ?? "") ?? .graphite
        minimal = defaults.bool(forKey: "minimal")
        alerts = defaults.object(forKey: "alerts") as? Bool ?? true
        autoSkin = defaults.bool(forKey: "autoSkin")
        sound = defaults.object(forKey: "sound") as? Bool ?? true
        approximateLocation = SharedStore.approximateLocation
        rules = NotificationRules.load(defaults)
        isPro = defaults.bool(forKey: ProStatus.cacheKey)
        SoundEngine.shared.enabled = sound
    }

    // MARK: Murk Pro

    static let freeSavedPlaces = 1

    /// Called by the entitlement store once the App Store has confirmed the subscription state.
    func setPro(_ pro: Bool) {
        isPro = pro
        guard !pro else { return }
        // Pro-only looks fall back to free ones. Saved cities are kept.
        if autoSkin { autoSkin = false }
        if skin.isPremium { skin = .graphite }
    }

    var canAddPlace: Bool { isPro || places.count < Self.freeSavedPlaces }

    /// Picks a skin, or shows the paywall if it needs Pro.
    func choose(_ s: Skin?) {
        if let s {
            if s.isPremium && !isPro { paywall = .skin; return }
            autoSkin = false; skin = s
        } else {
            if !isPro { paywall = .skin; return }
            autoSkin = true
        }
    }

    /// Pick a skin from the weather: warm on sunny days, aurora at night, storm in rain, fog when grey.
    func resolveAutoSkin() {
        guard autoSkin, isPro, let c = forecast?.current else { return }
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

    /// nil = current location (only when it's in use and allowed), then saved cities in order.
    var cityIDs: [String?] {
        var list: [String?] = (useLocation && !locationDenied) ? [nil] : []
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

    var activePlace: Place? {
        if let id = selectedID, let p = places.first(where: { $0.id == id }) { return p }
        if useLocation, let c = currentPlace { return c }
        return places.first
    }

    /// True only when the weather on screen really is for where the user is.
    var isFollowingLocation: Bool { selectedID == nil && useLocation && currentPlace != nil && !locationDenied }

    /// The saved city standing in while the current location can't be used.
    var fallbackPlace: Place? {
        guard selectedID == nil, !isFollowingLocation else { return nil }
        return places.first
    }

    // MARK: Actions

    func start() async {
        ForecastCache.removeLegacyFiles()
        if selectedID == nil, !useLocation, let first = places.first { selectedID = first.id }
        begin(force: false, locate: true)
        await loadTask?.value
    }

    /// People who had notifications before this version keep official alerts; nobody is prompted here.
    func migrateNotifications() async {
        guard defaults.object(forKey: NotificationRules.key) == nil else { return }
        var r = rules
        r.official = alerts ? await Notifier.isAuthorized() : false
        rules = r
    }

    /// The user asked for their own location. This is the only path that can show the permission prompt.
    func selectCurrentLocation() {
        useLocation = true
        selectedID = nil
        begin(force: true, locate: true)
    }

    func stopUsingLocation() {
        useLocation = false
        currentPlace = nil
        locationProblem = nil
        if selectedID == nil { selectedID = places.first?.id }
        begin(force: true, locate: false)
    }

    func select(_ place: Place) {
        selectedID = place.id
        begin(force: true, locate: false)
    }

    /// Returns false (and shows the paywall) if another saved city needs Pro.
    @discardableResult
    func add(_ place: Place) -> Bool {
        if places.contains(where: { $0.id == place.id }) { select(place); return true }
        guard canAddPlace else { paywall = .city; return false }
        places.append(place)
        select(place)
        return true
    }

    func remove(at offsets: IndexSet) {
        let removed = offsets.map { places[$0].id }
        places.remove(atOffsets: offsets)
        if let s = selectedID, removed.contains(s) {
            selectedID = useLocation ? nil : places.first?.id
            begin(force: true, locate: true)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        places.move(fromOffsets: source, toOffset: destination)
    }

    /// App came to the foreground. Does nothing if a load is running or the forecast is still fresh.
    func refreshIfStale() {
        if loadInFlight { return }
        if let f = forecast, let p = activePlace, Self.same(f.place, p), !f.isCached, f.age() < 600, selectedID != nil { return }
        begin(force: false, locate: true)
    }

    func retry() { begin(force: true, locate: true) }

    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }     // unknown links are ignored
        route = link
    }

    // MARK: Loading

    private func begin(force: Bool, locate: Bool) {
        loadTask?.cancel()
        generation += 1
        let gen = generation
        loadInFlight = true
        loadTask = Task { [weak self] in await self?.run(gen, force: force, locate: locate) }
    }

    private func isCurrent(_ gen: Int) -> Bool { gen == generation && !Task.isCancelled }

    private static func same(_ a: Place, _ b: Place) -> Bool {
        a.id == b.id && abs(a.latitude - b.latitude) < 0.05 && abs(a.longitude - b.longitude) < 0.05
    }

    private func run(_ gen: Int, force: Bool, locate: Bool) async {
        defer { if gen == generation { loadInFlight = false; isLoading = false } }
        if locate, selectedID == nil, useLocation { await self.locate(gen) }
        guard isCurrent(gen) else { return }
        guard let place = activePlace else { forecast = nil; return }

        if !force, let f = forecast, Self.same(f.place, place), !f.isCached, f.age() < 600 { return }
        if forecast.map({ !Self.same($0.place, place) }) ?? true {
            // Last known weather for this place right away; never the previous city's.
            forecast = repository.cached(for: place)
            failure = nil
            resolveAutoSkin()
        }
        isLoading = true
        do {
            var fresh = try await repository.core(for: place)
            guard isCurrent(gen) else { return }
            if let old = forecast, Self.same(old.place, place) { fresh.aqi = old.aqi; fresh.alerts = old.alerts }
            forecast = fresh
            failure = nil
            isLoading = false
            resolveAutoSkin()
            syncWidget()

            // Air quality and alerts arrive afterwards and never hold up the screen.
            let extras = await repository.extras(for: place)
            guard isCurrent(gen), var f = forecast, Self.same(f.place, place) else { return }
            if let a = extras.aqi { f.aqi = a }
            if extras.alertsLoaded { f.alerts = extras.alerts }
            forecast = f
            effects.notify(f, rules, unit, isPro)
        } catch is CancellationError {
        } catch {
            guard isCurrent(gen) else { return }
            failure = (error as? WeatherError) ?? .badData
        }
    }

    private func locate(_ gen: Int) async {
        do {
            let p = try await location.currentPlace()
            guard isCurrent(gen) else { return }
            currentPlace = p
            locationDenied = false
            locationProblem = nil
        } catch is CancellationError {
        } catch {
            guard isCurrent(gen) else { return }
            // Falls back to the first saved city (see activePlace), and says so.
            locationDenied = location.isDenied
            locationProblem = locationDenied ? .denied : ((error as? LocationError) ?? .unavailable)
            if locationDenied { currentPlace = nil }
        }
    }

    // MARK: Trust: how fresh is what's on screen

    struct Status: Equatable {
        var text: String
        var symbol: String
        var canRetry: Bool
        var isProblem: Bool
    }

    func status(now: Date = Date()) -> Status? {
        guard let f = forecast else {
            if isLoading { return Status(text: String(localized: "LOADING…"), symbol: "arrow.triangle.2.circlepath", canRetry: false, isProblem: false) }
            if let failure { return Status(text: Self.describe(failure) + " " + String(localized: "TAP TO RETRY"), symbol: Self.symbol(failure), canRetry: true, isProblem: true) }
            return nil
        }
        let age = Outlook.age(f.age(now: now))
        if let failure {
            let lead: String
            switch failure {
            case .offline: lead = String(localized: "OFFLINE")
            case .provider: lead = String(localized: "FORECAST SERVICE UNAVAILABLE")
            case .timedOut: lead = String(localized: "SLOW CONNECTION")
            case .badData: lead = String(localized: "COULDN'T READ THE FORECAST")
            }
            return Status(text: String(localized: "\(lead) · SAVED FORECAST FROM \(age) · TAP TO RETRY"), symbol: Self.symbol(failure), canRetry: true, isProblem: true)
        }
        if isLoading { return Status(text: String(localized: "REFRESHING… · LAST UPDATED \(age)"), symbol: "arrow.triangle.2.circlepath", canRetry: false, isProblem: false) }
        if f.isCached || f.isStale(now: now) {
            return Status(text: String(localized: "SAVED FORECAST FROM \(age) · TAP TO REFRESH"), symbol: "clock.arrow.circlepath", canRetry: true, isProblem: false)
        }
        return Status(text: String(localized: "UPDATED \(age) · FORECAST BY OPEN-METEO"), symbol: "checkmark.circle", canRetry: false, isProblem: false)
    }

    static func describe(_ e: WeatherError) -> String {
        switch e {
        case .offline: return String(localized: "YOU'RE OFFLINE.")
        case .timedOut: return String(localized: "THE FORECAST TOOK TOO LONG.")
        case .provider: return String(localized: "THE FORECAST SERVICE IS UNAVAILABLE.")
        case .badData: return String(localized: "THE FORECAST CAME BACK INCOMPLETE.")
        }
    }

    static func symbol(_ e: WeatherError) -> String {
        switch e {
        case .offline: return "wifi.slash"
        case .timedOut: return "hourglass"
        case .provider: return "exclamationmark.icloud"
        case .badData: return "questionmark.circle"
        }
    }

    // MARK: Widgets

    /// Hands the current forecast, place and look to the widgets.
    private func syncWidget() {
        effects.syncWidget(forecast, forecast?.place ?? activePlace, unit, skin)
    }

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
        let word = f.current.condition.precip == .snow ? String(localized: "SNOW") : String(localized: "RAIN")
        func mins(_ p: MinutePoint) -> Int { max(5, Int((p.time.timeIntervalSince(now) / 60 / 5).rounded()) * 5) }
        if raining {
            if let dry = pts.first(where: { !wet($0) }) { return String(localized: "\(word) STOPS IN \(mins(dry)) MIN") }
            return nil
        }
        if let first = pts.first(where: wet) { return String(localized: "\(word) IN \(mins(first)) MIN") }
        return nil
    }

    func dayLabel(_ d: DailyWeather, index: Int) -> String {
        if index == 0 { return String(localized: "TODAY") }
        let f = DateFormatter(); f.timeZone = forecast?.timeZone; f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: d.date).uppercased()
    }

    /// Clock time in the place's own zone, in the user's 12- or 24-hour style.
    func time(_ date: Date?) -> String {
        guard let date else { return "--" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = forecast?.timeZone ?? .current
        return date.formatted(style)
    }

    /// The most pressing official alert, if any.
    var topAlert: WeatherAlert? {
        guard let list = forecast?.alerts, !list.isEmpty else { return nil }
        return list.first(where: \.isSevere) ?? list.first
    }

    /// A short heads-up for the pill above the scene, or nil.
    var headsUp: String? {
        guard alerts, let f = forecast else { return nil }
        if let a = topAlert { return a.event.uppercased() }
        if let r = nextHourRain { return r }
        if f.current.condition.precip == .rain { return String(localized: "RAIN NOW") }
        if f.current.condition.precip == .snow { return String(localized: "SNOW NOW") }
        for (i, d) in f.daily.prefix(3).enumerated() where d.precipChance >= 40 {
            let when = i == 0 ? String(localized: "TODAY") : i == 1 ? String(localized: "TOMORROW") : dayLabel(d, index: i)
            return "\(d.precipChance)% \(d.condition.precip == .snow ? String(localized: "SNOW") : String(localized: "RAIN")) \(when)"
        }
        if let uv = f.daily.first?.uvMax, uv >= 8 { return String(localized: "UV \(Int(uv.rounded())) TODAY") }
        if let g = f.current.windGust, g >= 50 { return String(localized: "GUSTY WINDS") }
        return nil
    }
}

/// The real side effects: the widgets' shared files and system notifications.
enum LiveEffects {
    static let syncWidget: (Forecast?, Place?, TempUnit, Skin) -> Void = { forecast, place, unit, skin in
        if let place { SharedStore.place = place }
        SharedStore.unit = unit
        SharedStore.skin = skin
        if let forecast { WidgetSnapshot(forecast: forecast, unit: unit, skin: skin).save() }
        WidgetCenter.shared.reloadAllTimelines()
        let current = forecast.map { (ArtKind(code: $0.current.code), $0.current.isDay) }
        SceneSnapshotter.renderIfNeeded(skin: skin, first: current)
    }

    static let notify: (Forecast, NotificationRules, TempUnit, Bool) -> Void = { f, rules, unit, pro in
        AlertDispatcher.deliver(for: f, rules: rules, unit: unit, isPro: pro)
    }
}
