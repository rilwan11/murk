import Foundation
#if os(iOS) && canImport(ActivityKit)
import ActivityKit
#endif

/// What the Lock Screen countdown shows: when rain starts (or stops) and the next two hours in 15-minute bars.
struct RainCountdown: Codable, Hashable {
    enum Kind: String, Codable { case starts, stops }
    var kind: Kind
    /// When the change happens.
    var at: Date
    /// Rain in each of the next eight 15-minute slots, in mm. The first slot starts at `from`.
    var bars: [Double]
    var from: Date
    var snow: Bool

    static let wet = 0.1          // mm in 15 minutes
    static let lookahead: TimeInterval = 60 * 60

    /// A countdown is worth showing only when the change is within the hour.
    static func plan(_ f: Forecast, now: Date = Date()) -> RainCountdown? {
        let slots = f.minutely.filter { $0.time.addingTimeInterval(900) > now }.prefix(8)
        guard let first = slots.first else { return nil }
        let snow = f.current.condition.precip == .snow || (f.hourly.first { $0.time.addingTimeInterval(3600) > now }?.snowfall ?? 0) > 0
        let bars = slots.map { max(0, $0.precip) }
        let rainingNow = first.precip >= wet || (f.current.precipitation ?? 0) > 0.05
        let horizon = now.addingTimeInterval(lookahead)
        if rainingNow {
            guard let dry = slots.dropFirst().first(where: { $0.precip < wet }), dry.time <= horizon else { return nil }
            return RainCountdown(kind: .stops, at: dry.time, bars: bars, from: first.time, snow: snow)
        }
        guard let wetSlot = slots.first(where: { $0.precip >= wet }), wetSlot.time <= horizon else { return nil }
        return RainCountdown(kind: .starts, at: max(wetSlot.time, now), bars: bars, from: first.time, snow: snow)
    }

    var word: String { snow ? String(localized: "Snow") : String(localized: "Rain") }

    /// "Rain in" / "Dry in", shown before the timer.
    var lead: String {
        kind == .starts ? String(localized: "\(word) in") : String(localized: "Dry in")
    }

    /// Shown once the moment has passed.
    var arrived: String {
        kind == .starts ? String(localized: "\(word) now") : String(localized: "Dry now")
    }

    var symbol: String {
        switch kind {
        case .starts: return snow ? "cloud.snow.fill" : "cloud.rain.fill"
        case .stops: return "cloud.sun.fill"
        }
    }

    /// 0…1 for drawing, 4 mm per 15 minutes is a downpour.
    var levels: [Double] { bars.map { min(1, $0 / 4) } }
}

#if os(iOS) && canImport(ActivityKit)
struct RainActivityAttributes: ActivityAttributes {
    typealias ContentState = RainCountdown
    var place: String
}
#endif
