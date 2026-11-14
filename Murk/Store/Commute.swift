import Foundation

/// When the user travels each day. Each trip is checked as a one-hour window.
struct CommuteTimes: Codable, Equatable {
    var morning = 8      // hour the trip out starts, 0–23
    var evening = 17     // hour the trip home starts, 0–23

    var windows: [(Int, Int)] { [(morning, morning + 1), (evening, evening + 1)] }

    static let key = "commute"

    static func load(_ d: UserDefaults) -> CommuteTimes {
        guard let data = d.data(forKey: key), let c = try? JSONDecoder().decode(CommuteTimes.self, from: data) else { return CommuteTimes() }
        return c
    }

    func save(_ d: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { d.set(data, forKey: Self.key) }
    }

    /// "8 AM" or "08:00" following the user's locale.
    static func label(_ hour: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = 0
        let date = Calendar(identifier: .gregorian).date(from: c) ?? Date()
        return date.formatted(.dateTime.hour())
    }
}
