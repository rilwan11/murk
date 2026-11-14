import Foundation

/// "What changes next": one short line about the next notable shift in the coming hours.
enum Outlook {
    /// Looks up to 18 hours ahead for rain starting or stopping, a strong gust, or a big temperature swing.
    static func summary(_ f: Forecast, unit: TempUnit, now: Date = Date()) -> String? {
        let ahead = f.hourly.filter { $0.time > now.addingTimeInterval(-1800) && $0.time < now.addingTimeInterval(18 * 3600) }
        guard ahead.count >= 3 else { return nil }
        func hour(_ d: Date) -> String {
            let fmt = DateFormatter(); fmt.timeZone = f.timeZone; fmt.setLocalizedDateFormatFromTemplate("j")
            return fmt.string(from: d).uppercased()
        }
        func wet(_ h: HourlyPoint) -> Bool { h.condition.precip != .none || h.precipChance >= 60 }
        let word: (HourlyPoint) -> String = { $0.condition.precip == .snow ? String(localized: "SNOW") : String(localized: "RAIN") }

        let wetNow = f.current.condition.precip != .none
        if wetNow {
            if let dry = ahead.dropFirst().first(where: { !wet($0) }) {
                return String(localized: "\(word(ahead[0])) EASES AROUND \(hour(dry.time))")
            }
        } else if let first = ahead.dropFirst().first(where: wet) {
            return String(localized: "\(word(first)) LIKELY AROUND \(hour(first.time))")
        }

        if let peak = ahead.max(by: { ($0.windGust ?? 0) < ($1.windGust ?? 0) }), let g = peak.windGust, g >= 45,
           g >= (f.current.windGust ?? 0) + 10 {
            return String(localized: "GUSTS TO \(unit.wind(g)) AROUND \(hour(peak.time))")
        }

        let nowTemp = unit.temp(f.current.temperature)
        if let swing = ahead.max(by: { abs($0.temperature - f.current.temperature) < abs($1.temperature - f.current.temperature) }) {
            let delta = unit.temp(swing.temperature) - nowTemp
            let big = unit == .fahrenheit ? 10 : 6
            if abs(delta) >= big {
                return delta > 0 ? String(localized: "\(delta)° WARMER BY \(hour(swing.time))")
                                 : String(localized: "\(-delta)° COOLER BY \(hour(swing.time))")
            }
        }
        return nil
    }

    /// "JUST NOW", "12 MIN AGO", "3 HR AGO".
    static func age(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        if m < 1 { return String(localized: "JUST NOW") }
        if m < 60 { return String(localized: "\(m) MIN AGO") }
        let h = m / 60
        if h < 48 { return String(localized: "\(h) HR AGO") }
        return String(localized: "\(h / 24) DAYS AGO")
    }
}
