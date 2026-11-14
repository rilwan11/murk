import Foundation
import UserNotifications

/// Which weather the user wants to be told about, and at what level. Official alerts are free;
/// the threshold rules below are part of Murk Pro.
struct NotificationRules: Codable, Equatable {
    var official = false
    var rain = false
    var rainChance = 60          // percent
    var wind = false
    var gustKmh = 50.0
    var aqi = false
    var aqiLevel = 101
    var uv = false
    var uvLevel = 8.0

    var anyAdvanced: Bool { rain || wind || aqi || uv }

    struct Notice: Equatable {
        /// Stable per rule and day, so each fires once a day per place at most.
        var id: String
        var title: String
        var body: String
    }

    /// Notices the forecast warrants right now. `advanced` is false without Murk Pro.
    func notices(for f: Forecast, unit: TempUnit, advanced: Bool, now: Date = Date()) -> [Notice] {
        guard advanced else { return [] }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone
        let c = cal.dateComponents([.year, .month, .day], from: now)
        let day = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        let next = f.hourly.filter { $0.time > now && $0.time < now.addingTimeInterval(12 * 3600) }
        func hour(_ d: Date) -> String {
            let fmt = DateFormatter(); fmt.timeZone = f.timeZone; fmt.setLocalizedDateFormatFromTemplate("j")
            return fmt.string(from: d)
        }
        var out: [Notice] = []
        if rain, f.current.condition.precip == .none, let h = next.first(where: { $0.precipChance >= rainChance }) {
            out.append(Notice(id: "rule.rain.\(day)", title: String(localized: "Rain likely · \(f.place.name)"),
                              body: String(localized: "\(h.precipChance)% chance around \(hour(h.time)).")))
        }
        if wind, let h = next.max(by: { ($0.windGust ?? 0) < ($1.windGust ?? 0) }), let g = h.windGust, g >= gustKmh {
            out.append(Notice(id: "rule.wind.\(day)", title: String(localized: "Strong gusts · \(f.place.name)"),
                              body: String(localized: "Gusts to \(unit.wind(g).lowercased()) around \(hour(h.time)).")))
        }
        if aqi, let v = f.aqi, v >= aqiLevel {
            out.append(Notice(id: "rule.aqi.\(day)", title: String(localized: "Air quality · \(f.place.name)"),
                              body: String(localized: "AQI is \(v) (\(aqiLabel(v).capitalized)).")))
        }
        if uv, let h = next.max(by: { ($0.uvIndex ?? 0) < ($1.uvIndex ?? 0) }), let u = h.uvIndex, u >= uvLevel {
            out.append(Notice(id: "rule.uv.\(day)", title: String(localized: "High UV · \(f.place.name)"),
                              body: String(localized: "UV index reaches \(Int(u.rounded())) around \(hour(h.time)).")))
        }
        return out
    }

    // MARK: Storage (shared by the app and its background refresh)

    static let key = "notificationRules"
    static func load(_ d: UserDefaults = .standard) -> NotificationRules {
        guard let data = d.data(forKey: key), let r = try? JSONDecoder().decode(NotificationRules.self, from: data) else { return NotificationRules() }
        return r
    }
    func save(_ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.key) }
    }
}

extension Place {
    /// Identifies a place for "already notified" bookkeeping, the same way in the app and in the background.
    var alertScope: String {
        isCurrentLocation ? "current" : "city|\(name)"
    }
}

/// Turns a forecast into notifications, each at most once. Used in the foreground and the background.
enum AlertDispatcher {
    typealias Post = (_ id: String, _ title: String, _ body: String) -> Void

    /// Returns what was posted (for tests).
    @discardableResult
    static func deliver(for f: Forecast, rules: NotificationRules, unit: TempUnit, isPro: Bool,
                        ledger: AlertLedger = AlertLedger(), now: Date = Date(),
                        post: Post = Notifier.post) -> [String] {
        let scope = f.place.alertScope
        var posted: [String] = []
        if rules.official, !f.alerts.isEmpty {
            let fresh = Set(ledger.claim(f.alerts.map(\.id), scope: scope, now: now))
            for a in f.alerts where fresh.contains(a.id) {
                post("\(scope)|\(a.id)", "\(a.event) · \(f.place.name)", a.headline)
                posted.append(a.id)
            }
        }
        let notices = rules.notices(for: f, unit: unit, advanced: isPro, now: now)
        if !notices.isEmpty {
            let fresh = Set(ledger.claim(notices.map(\.id), scope: scope, now: now))
            for n in notices where fresh.contains(n.id) {
                post("\(scope)|\(n.id)", n.title, n.body)
                posted.append(n.id)
            }
        }
        return posted
    }
}


/// The system notification permission and posting. Permission is only requested when the user turns an alert on.
enum Notifier {
    static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return s == .authorized || s == .provisional || s == .ephemeral
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Shows the system prompt the first time; afterwards just reports the current answer.
    static func request() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Posts only if the user has allowed notifications. Never prompts.
    static let post: AlertDispatcher.Post = { id, title, body in
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
        }
    }
}
