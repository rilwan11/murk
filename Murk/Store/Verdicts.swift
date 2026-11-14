import Foundation

/// The big answer and one-line verdict each page shows. Pure functions of the forecast, so they can be tested.
struct Verdict: Equatable {
    /// Shown in the big sculpted type ("3 PM", "12", "3h 12m").
    var big: String
    /// A small word beside the big one ("mph", "%"), or empty.
    var unit: String = ""
    /// One plain sentence.
    var line: String
}

enum Verdicts {
    private static func clock(_ d: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = tz
        return d.formatted(style)
    }

    /// "3 PM" style, or "3:30 PM" when the minutes matter.
    private static func hourWord(_ d: Date, _ tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        if cal.component(.minute, from: d) == 0 {
            var style = Date.FormatStyle(date: .omitted, time: .omitted).hour(.defaultDigits(amPM: .abbreviated))
            style.timeZone = tz
            return d.formatted(style)
        }
        return clock(d, tz)
    }

    private static func dayWord(_ d: Date, now: Date, _ tz: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        if cal.isDate(d, inSameDayAs: now) { return "" }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(d, inSameDayAs: t) { return String(localized: "tomorrow ") }
        var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.wide)
        style.timeZone = tz
        return d.formatted(style) + " "
    }

    private static func minutesText(_ s: TimeInterval) -> String {
        let m = max(5, Int((s / 60 / 5).rounded()) * 5)
        return m < 60 ? String(localized: "\(m) min") : String(localized: "\(m / 60)h \(m % 60)m")
    }

    // MARK: Rain

    static func isWet(_ h: HourlyPoint) -> Bool { h.precipChance >= 50 || h.precip >= 0.2 }

    /// When rain (or snow) starts or stops, or how long it stays dry.
    static func rain(_ f: Forecast, now: Date = Date(), unit: TempUnit) -> Verdict {
        let tz = f.timeZone
        let snow = f.current.condition.precip == .snow
        let word = snow ? String(localized: "Snow") : String(localized: "Rain")
        let soon = f.minutely.filter { $0.time.addingTimeInterval(900) > now && $0.time < now.addingTimeInterval(3 * 3600) }
        let ahead = f.hourly.filter { $0.time.addingTimeInterval(3600) > now }
        let rainingNow = (f.current.precipitation ?? 0) > 0.05 || (soon.first.map { $0.precip >= 0.1 } ?? false)
            || f.current.condition.precip != .none

        if rainingNow {
            if let dry = soon.first(where: { $0.precip < 0.1 }), dry.time > now {
                return Verdict(big: minutesText(dry.time.timeIntervalSince(now)),
                               line: String(localized: "\(word) stops in about \(minutesText(dry.time.timeIntervalSince(now)))"))
            }
            if let dry = ahead.dropFirst().first(where: { !isWet($0) }) {
                let total = ahead.prefix { isWet($0) }.reduce(0) { $0 + $1.precip }
                return Verdict(big: hourWord(dry.time, tz),
                               line: String(localized: "\(word) until about \(hourWord(dry.time, tz)), \(unit.precip(total).lowercased()) more"))
            }
            return Verdict(big: String(localized: "Now"), line: String(localized: "\(word) on and off all day"))
        }
        if let wet = soon.first(where: { $0.precip >= 0.1 }) {
            let mins = minutesText(wet.time.timeIntervalSince(now))
            return Verdict(big: mins, line: String(localized: "\(word) starts in about \(mins)"))
        }
        if let start = ahead.prefix(48).firstIndex(where: isWet) {
            let h = ahead[start]
            let spell = ahead[start...].prefix { isWet($0) }
            let total = spell.reduce(0) { $0 + $1.precip }
            let w = (h.snowfall ?? 0) > 0 ? String(localized: "Snow") : word
            let when = dayWord(h.time, now: now, tz) + String(localized: "around ") + hourWord(h.time, tz)
            let amount = total >= 0.1 ? String(localized: ", about \(unit.precip(total).lowercased())") : ""
            return Verdict(big: hourWord(h.time, tz), line: "\(w) " + String(localized: "starts \(when)") + amount)
        }
        let dryDays = f.daily.prefix(7).prefix { $0.precipChance < 30 }.count
        if dryDays >= 2 {
            return Verdict(big: String(localized: "Dry"), line: String(localized: "Dry for the next \(dryDays) days"))
        }
        return Verdict(big: String(localized: "Dry"), line: String(localized: "No rain in the next two days"))
    }

    /// The morning and evening commute windows: dry, or how likely rain is.
    static func commute(_ f: Forecast, now: Date = Date(), windows: [(Int, Int)] = [(8, 9), (17, 18)]) -> [(String, String)] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone
        return windows.map { (start: Int, end: Int) -> (String, String) in
            var day = cal.startOfDay(for: now)
            if cal.component(.hour, from: now) >= end { day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
            let from = day.addingTimeInterval(Double(start) * 3600), to = day.addingTimeInterval(Double(end) * 3600)
            let hours = f.hourly.filter { $0.time >= from && $0.time <= to }
            let chance = hours.map(\.precipChance).max() ?? 0
            let label = (cal.isDate(day, inSameDayAs: now) ? "" : String(localized: "Tomorrow ")) + "\(hourWord(from, f.timeZone))–\(hourWord(to, f.timeZone))"
            let verdict = chance < 30 ? String(localized: "Dry") : String(localized: "Umbrella, \(chance)%")
            return (label, verdict)
        }
    }

    // MARK: Wind and air

    static func windWord(_ kmh: Double) -> String {
        switch kmh {
        case ..<5: return String(localized: "Calm")
        case ..<20: return String(localized: "Light wind")
        case ..<35: return String(localized: "Breezy")
        case ..<50: return String(localized: "Windy")
        default: return String(localized: "Very windy")
        }
    }

    static func wind(_ f: Forecast, at hour: HourlyPoint?, now: Date = Date(), unit: TempUnit) -> Verdict {
        let speed = hour?.windSpeed ?? f.current.windSpeed ?? 0
        let from = hour?.windDirection ?? f.current.windDirection ?? 0
        let unitWord = unit == .fahrenheit ? "mph" : "km/h"
        let next = f.hourly.filter { $0.time >= now.addingTimeInterval(-1800) && $0.time < now.addingTimeInterval(24 * 3600) }
        let peak = next.max { ($0.windGust ?? $0.windSpeed) < ($1.windGust ?? $1.windSpeed) }
        let line: String
        if let peak, let g = peak.windGust, g >= 30 {
            line = String(localized: "Gusts to \(Int(unit.windValue(g).rounded())) \(unitWord) around \(hourWord(peak.time, f.timeZone))")
        } else if next.allSatisfy({ $0.windSpeed < 5 }) {
            line = String(localized: "Calm all day")
        } else {
            line = String(localized: "\(windWord(speed)) from the \(from.compassDirection), no strong gusts")
        }
        return Verdict(big: "\(Int(unit.windValue(speed).rounded()))", unit: "\(unitWord) \(from.compassDirection)", line: line)
    }

    /// Dew point in °C → how the air feels.
    static func dewWord(_ c: Double) -> String {
        let f = c * 9 / 5 + 32
        switch f {
        case ..<50: return String(localized: "Dry")
        case ..<60: return String(localized: "Comfortable")
        case ..<65: return String(localized: "A little humid")
        default: return String(localized: "Sticky")
        }
    }

    enum Trend: Equatable { case rising, steady, falling }

    /// Sea-level pressure change over the 3 hours to `now`.
    static func pressureTrend(_ hours: [HourlyPoint], now: Date = Date()) -> Trend? {
        let nowH = hours.min { abs($0.time.timeIntervalSince(now)) < abs($1.time.timeIntervalSince(now)) }
        let before = hours.min { abs($0.time.timeIntervalSince(now.addingTimeInterval(-3 * 3600))) < abs($1.time.timeIntervalSince(now.addingTimeInterval(-3 * 3600))) }
        guard let a = before?.pressure, let b = nowH?.pressure else { return nil }
        if b - a > 1 { return .rising }
        if b - a < -1 { return .falling }
        return .steady
    }

    static func aqiWord(_ v: Int) -> String {
        switch v {
        case ..<51: return String(localized: "Good")
        case ..<101: return String(localized: "Moderate")
        case ..<151: return String(localized: "Unhealthy for sensitive groups")
        case ..<201: return String(localized: "Unhealthy")
        case ..<301: return String(localized: "Very unhealthy")
        default: return String(localized: "Hazardous")
        }
    }

    /// AQI category color as hex (EPA scale).
    static func aqiHex(_ v: Int) -> UInt32 {
        switch v {
        case ..<51: return 0x3CC864
        case ..<101: return 0xF2C230
        case ..<151: return 0xF08A2C
        case ..<201: return 0xE5484D
        case ..<301: return 0x9C4DCC
        default: return 0x7E2135
        }
    }

    // MARK: Sun

    struct SunDay {
        var sunrise: Date?
        var sunset: Date?
        var noon: Date?
        var goldenMorningEnd: Date?
        var goldenEveningStart: Date?
        var civilDawn: Date?, civilDusk: Date?
        var nauticalDawn: Date?, nauticalDusk: Date?
        var astroDawn: Date?, astroDusk: Date?
    }

    static func sunDay(latitude: Double, longitude: Double, day: Date, timeZone: TimeZone) -> SunDay {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = timeZone
        let start = cal.startOfDay(for: day)
        let alt: (Date) -> Double = { Astronomy.sunPosition(latitude: latitude, longitude: longitude, at: $0).altitude }
        func up(_ th: Double) -> Date? { Astronomy.crossing(from: start, threshold: th, rising: true, altitude: alt) }
        func down(_ th: Double) -> Date? { Astronomy.crossing(from: start.addingTimeInterval(6 * 3600), hours: 18, threshold: th, rising: false, altitude: alt) }
        let rise = up(Astronomy.horizonAltitude), set = down(Astronomy.horizonAltitude)
        var noon: Date? = nil
        if let rise, let set { noon = rise.addingTimeInterval(set.timeIntervalSince(rise) / 2) }
        return SunDay(sunrise: rise, sunset: set, noon: noon,
                      goldenMorningEnd: up(Astronomy.goldenTop), goldenEveningStart: down(Astronomy.goldenTop),
                      civilDawn: up(Astronomy.civil), civilDusk: down(Astronomy.civil),
                      nauticalDawn: up(Astronomy.nautical), nauticalDusk: down(Astronomy.nautical),
                      astroDawn: up(Astronomy.astronomical), astroDusk: down(Astronomy.astronomical))
    }

    static func hm(_ s: TimeInterval) -> String {
        let m = max(0, Int(s / 60))
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    static func sun(_ f: Forecast, now: Date = Date()) -> Verdict {
        let lat = f.place.latitude, lon = f.place.longitude, tz = f.timeZone
        let today = sunDay(latitude: lat, longitude: lon, day: now, timeZone: tz)
        if let rise = today.sunrise, let set = today.sunset, now >= rise, now < set {
            let golden = today.goldenEveningStart.map { $0 > now ? String(localized: "; golden hour from \(clock($0, tz))") : String(localized: "; golden hour now") } ?? ""
            return Verdict(big: hm(set.timeIntervalSince(now)), unit: String(localized: "of daylight left"),
                           line: String(localized: "Sunset at \(clock(set, tz))") + golden)
        }
        var next = today.sunrise.flatMap { $0 > now ? $0 : nil }
        if next == nil {
            next = sunDay(latitude: lat, longitude: lon, day: now.addingTimeInterval(86400), timeZone: tz).sunrise
        }
        guard let rise = next else {
            let alt = Astronomy.sunPosition(latitude: lat, longitude: lon, at: now).altitude
            return alt > 0 ? Verdict(big: "24h", line: String(localized: "The sun doesn't set today"))
                           : Verdict(big: String(localized: "Night"), line: String(localized: "The sun doesn't rise today"))
        }
        return Verdict(big: hm(rise.timeIntervalSince(now)), unit: String(localized: "until sunrise"),
                       line: String(localized: "Sunrise at \(clock(rise, tz))"))
    }

    /// "Sunscreen from 10 AM to 2 PM", or nil when UV stays low.
    static func uvAdvice(_ f: Forecast, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone
        let today = f.hourly.filter { cal.isDate($0.time, inSameDayAs: now) }
        let high = today.filter { ($0.uvIndex ?? 0) >= 3 }
        guard let first = high.first, let last = high.last else { return String(localized: "UV stays low today: no sunscreen needed") }
        return String(localized: "Sunscreen from \(hourWord(first.time, f.timeZone)) to \(hourWord(last.time.addingTimeInterval(3600), f.timeZone))")
    }

    // MARK: Moon

    struct MoonNight {
        var rise: Date?
        var set: Date?
        var upNow: Bool
        /// Average cloud cover (%) over the hours the moon is up between sunset and sunrise.
        var cloud: Double?
    }

    static func moonNight(_ f: Forecast, now: Date = Date()) -> MoonNight {
        let lat = f.place.latitude, lon = f.place.longitude
        let alt: (Date) -> Double = { Astronomy.moonAltitude(latitude: lat, longitude: lon, at: $0) }
        let upNow = alt(now) > 0.125
        let rise = Astronomy.crossing(from: now, threshold: 0.125, rising: true, altitude: alt)
        let set = Astronomy.crossing(from: now, threshold: 0.125, rising: false, altitude: alt)
        let night = f.hourly.filter {
            $0.time > now.addingTimeInterval(-3600) && $0.time < now.addingTimeInterval(18 * 3600) && !$0.isDay && alt($0.time) > 0
        }
        let covers = night.compactMap(\.cloudCover)
        let cloud = covers.isEmpty ? nil : covers.reduce(0, +) / Double(covers.count)
        return MoonNight(rise: rise, set: set, upNow: upNow, cloud: cloud)
    }

    static func moon(_ f: Forecast, now: Date = Date()) -> Verdict {
        let age = Astronomy.moonAge(now)
        let k = Int((Astronomy.illumination(age: age) * 100).rounded())
        let n = moonNight(f, now: now)
        let tz = f.timeZone
        var when: String
        if n.upNow, let set = n.set { when = String(localized: "Up until \(clock(set, tz))") }
        else if let rise = n.rise { when = String(localized: "Rises at \(clock(rise, tz))") }
        else { when = String(localized: "Below the horizon today") }
        if let c = n.cloud {
            if c < 30 { when += String(localized: ", clear skies: a good night to look") }
            else if c > 70 { when = String(localized: "Hidden by cloud tonight") }
            else { when += String(localized: ", with some cloud") }
        }
        return Verdict(big: "\(k)", unit: "% · " + Astronomy.phaseName(age: age), line: when)
    }
}
