import Foundation
import SwiftUI
import WidgetKit
import UIKit
import UserNotifications

/// Why the paywall is being shown (always a moment where Pro adds something the user just asked for).
enum PaywallReason: String, Identifiable {
    case city, skin, alerts, overview, icon, sync, general
    var id: String { rawValue }
}

/// Presentation state and user actions. Data access lives in `WeatherRepository`.
@MainActor
final class AppState: ObservableObject {
    /// Things that reach outside the app, replaceable in tests.
    struct Effects {
        var syncWidget: (Forecast?, Place?, TempUnit, Skin) -> Void = LiveEffects.syncWidget
        var notify: (Forecast, NotificationRules, TempUnit, Bool) -> Void = LiveEffects.notify
        /// Saved cities and Pro status, for widgets pinned to a city.
        var shareLibrary: ([Place], Bool) -> Void = LiveEffects.shareLibrary
        /// The rain countdown on the Lock Screen.
        var liveActivity: (Forecast?, Bool) -> Void = LiveEffects.liveActivity
    }

    // Places
    @Published var places: [Place] { didSet { savePlaces(); effects.shareLibrary(places, isPro) } }
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
    /// The hour the slider is on, shared by every page (index into `upcomingHours`; nil = now).
    @Published var selectedHour: Int?
    /// Days from today the Moon page's slider is on (0 = tonight).
    @Published var moonDayOffset: Double = 0

    // Settings
    @Published var unit: TempUnit { didSet { defaults.set(unit.rawValue, forKey: "unit"); syncWidget() } }
    @Published var skin: Skin { didSet { defaults.set(skin.rawValue, forKey: "skin"); syncWidget() } }
    @Published var minimal: Bool { didSet { defaults.set(minimal, forKey: "minimal") } }
    /// The Now page also shows the temperature in the other unit.
    @Published var bothUnits: Bool { didSet { defaults.set(bothUnits, forKey: "bothUnits"); SharedStore.bothUnits = bothUnits; WidgetCenter.shared.reloadAllTimelines() } }
    /// Tilting the phone tilts the 3D scenes.
    @Published var tilt: Bool { didSet { defaults.set(tilt, forKey: MotionTilt.settingKey) } }
    /// The heads-up pill above the scene.
    @Published var alerts: Bool { didSet { defaults.set(alerts, forKey: "alerts") } }
    @Published var autoSkin: Bool { didSet { defaults.set(autoSkin, forKey: "autoSkin"); if autoSkin { resolveAutoSkin() } } }
    @Published var sound: Bool { didSet { defaults.set(sound, forKey: "sound"); SoundEngine.shared.enabled = sound } }
    @Published var approximateLocation: Bool { didSet { SharedStore.approximateLocation = approximateLocation } }
    @Published var rules: NotificationRules { didSet { rules.save(defaults) } }
    @Published var commute: CommuteTimes { didSet { commute.save(defaults) } }
    /// Show a Lock Screen countdown when rain is about to start or stop (Murk Pro).
    @Published var rainLiveActivity: Bool { didSet { defaults.set(rainLiveActivity, forKey: "rainLiveActivity"); syncLiveActivity() } }
    @Published private(set) var isPro: Bool

    private let defaults: UserDefaults
    private let location: LocationProviding
    let repository: WeatherProviding
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
        bothUnits = defaults.bool(forKey: "bothUnits")
        SharedStore.bothUnits = defaults.bool(forKey: "bothUnits")
        tilt = defaults.object(forKey: MotionTilt.settingKey) as? Bool ?? true
        alerts = defaults.object(forKey: "alerts") as? Bool ?? true
        autoSkin = defaults.bool(forKey: "autoSkin")
        sound = defaults.object(forKey: "sound") as? Bool ?? true
        approximateLocation = SharedStore.approximateLocation
        rules = NotificationRules.load(defaults)
        commute = CommuteTimes.load(defaults)
        rainLiveActivity = defaults.object(forKey: "rainLiveActivity") as? Bool ?? true
        isPro = defaults.bool(forKey: ProStatus.cacheKey)
        SoundEngine.shared.enabled = sound
    }

    // MARK: Murk Pro

    static let freeSavedPlaces = 1

    /// Called by the entitlement store once the App Store has confirmed the subscription state.
    func setPro(_ pro: Bool) {
        isPro = pro
        effects.shareLibrary(places, pro)
        syncLiveActivity()
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

    // MARK: iCloud sync (settings and saved cities only; never where the user is or has been)

    var syncedSettings: SyncedSettings {
        SyncedSettings(places: places, unit: unit.rawValue, skin: skin.rawValue, autoSkin: autoSkin,
                       minimal: minimal, headsUp: alerts, sound: sound, rules: rules)
    }

    /// Takes settings that arrived from another of the user's devices.
    func apply(_ s: SyncedSettings) {
        guard s != syncedSettings else { return }
        if s.places != places {
            places = s.places
            if let id = selectedID, !places.contains(where: { $0.id == id }) {
                selectedID = useLocation ? nil : places.first?.id
                begin(force: true, locate: true)
            }
        }
        if let u = TempUnit(rawValue: s.unit), u != unit { unit = u }
        if let k = Skin(rawValue: s.skin), k != skin, isPro || !k.isPremium { skin = k }
        if s.autoSkin != autoSkin, isPro || !s.autoSkin { autoSkin = s.autoSkin }
        if s.minimal != minimal { minimal = s.minimal }
        if s.headsUp != alerts { alerts = s.headsUp }
        if s.sound != sound { sound = s.sound }
        // Notification switches stay per device: each device has its own permission.
        var r = s.rules
        r.official = rules.official; r.rain = rules.rain; r.wind = rules.wind; r.aqi = rules.aqi; r.uv = rules.uv
        if r != rules { rules = r }
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
        effects.shareLibrary(places, isPro)
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
        // Coming back hours later: show the old forecast as the hour it is now while the new one loads.
        if let f = forecast, f.age() > 30 * 60 { forecast = f.rolled(to: Date()) }
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
            // A saved forecast reads as the hour it is now (an old "Sunny" mustn't show at night).
            forecast = (repository.cached(for: place) ?? nearbyCached(place))?.rolled(to: Date())
            failure = nil
            resolveAutoSkin()
            // Widgets switch place with the app right away, not only after a successful refresh.
            syncWidget()
        }
        isLoading = true
        do {
            var fresh = try await repository.core(for: place)
            guard isCurrent(gen) else { return }
            if let old = forecast, Self.same(old.place, place) { fresh.aqi = old.aqi; fresh.air = old.air; fresh.alerts = old.alerts }
            forecast = fresh
            failure = nil
            retries = 0
            isLoading = false
            resolveAutoSkin()
            syncWidget()

            // Air quality and alerts arrive afterwards and never hold up the screen.
            let extras = await repository.extras(for: place)
            guard isCurrent(gen), var f = forecast, Self.same(f.place, place) else { return }
            if let a = extras.aqi { f.aqi = a }
            if let q = extras.air { f.air = q }
            if extras.alertsLoaded { f.alerts = extras.alerts }
            forecast = f
            effects.notify(f, rules, unit, isPro)
        } catch is CancellationError {
        } catch {
            guard isCurrent(gen) else { return }
            let e = (error as? WeatherError) ?? .badData
            failure = e
            if let f = forecast, f.age() > 30 * 60 { forecast = f.rolled(to: Date()) }
            scheduleRetry(after: e, gen: gen)
        }
    }

    /// A saved forecast for another of the user's places within about 10 km (current location vs. the same
    /// city saved), so a slow network never leaves the screen empty.
    private func nearbyCached(_ place: Place) -> Forecast? {
        let near = ([currentPlace].compactMap { $0 } + places).filter {
            $0.id != place.id && abs($0.latitude - place.latitude) < 0.1 && abs($0.longitude - place.longitude) < 0.1
        }
        for other in near {
            if var f = repository.cached(for: other) { f.place = place; return f }
        }
        return nil
    }

    private var retries = 0

    /// A timeout or a dropped connection is tried again on its own: after 10 s, 30 s, then 90 s.
    private func scheduleRetry(after e: WeatherError, gen: Int) {
        guard e == .timedOut || e == .offline, retries < 3 else { return }
        let delay = [10.0, 30.0, 90.0][retries]
        retries += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.generation == gen, self.failure != nil,
                  UIApplication.shared.applicationState == .active else { return }
            self.begin(force: true, locate: false)
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
        syncLiveActivity()
    }

    func syncLiveActivity() {
        effects.liveActivity(forecast, rainLiveActivity && isPro)
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
        if let forecast {
            let snapshot = WidgetSnapshot(forecast: forecast, unit: unit, skin: skin)
            snapshot.save()
            // Widgets pinned to this city read their own copy.
            if !forecast.place.isCurrentLocation { snapshot.save(to: WidgetSnapshot.url(placeID: forecast.place.id)) }
        }
        WidgetCenter.shared.reloadAllTimelines()
        let current = forecast.map { (ArtKind(code: $0.current.code), $0.current.isDay) }
        SceneSnapshotter.renderIfNeeded(skin: skin, first: current)
    }

    static let shareLibrary: ([Place], Bool) -> Void = { places, pro in
        let shared = places.map(SharedPlace.init)
        guard shared != SharedStore.places || pro != SharedStore.isPro else { return }
        SharedStore.places = shared
        SharedStore.isPro = pro
        WidgetCenter.shared.reloadAllTimelines()
    }

    static let liveActivity: (Forecast?, Bool) -> Void = { f, on in
        Task { @MainActor in RainLiveActivity.sync(f, enabled: on) }
    }

    static let notify: (Forecast, NotificationRules, TempUnit, Bool) -> Void = { f, rules, unit, pro in
        AlertDispatcher.deliver(for: f, rules: rules, unit: unit, isPro: pro)
    }
}
