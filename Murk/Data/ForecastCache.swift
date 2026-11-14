import Foundation
import CryptoKit

/// Last-known forecasts on disk, so the app opens with weather even with no signal.
/// File names are hashes (no coordinates or city names), writes are atomic and protected,
/// entries carry a format version, and old or surplus entries are removed.
struct ForecastCache {
    static let version = 2

    var directory: URL
    /// Older than this is never shown.
    var maxAge: TimeInterval = 48 * 3600
    var maxEntries = 12

    struct Entry: Codable {
        var version: Int
        var savedAt: Date
        var body: Data
    }

    static var standard: ForecastCache? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return ForecastCache(directory: base.appendingPathComponent("forecasts", isDirectory: true))
    }

    /// A stable, non-revealing name for a place: a hash of its coordinates rounded to ~1 km.
    static func key(latitude: Double, longitude: Double) -> String {
        let s = "murk-cache-v\(version)|\(Coordinate.string(latitude, places: 2))|\(Coordinate.string(longitude, places: 2))"
        return SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    func url(for place: Place) -> URL {
        directory.appendingPathComponent("\(Self.key(latitude: place.latitude, longitude: place.longitude)).fc")
    }

    func save(_ body: Data, for place: Place, at date: Date = Date()) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(Entry(version: Self.version, savedAt: date, body: body)) else { return }
        try? data.write(to: url(for: place), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        prune(now: date)
    }

    func load(for place: Place, now: Date = Date()) -> (body: Data, savedAt: Date)? {
        let u = url(for: place)
        guard let data = try? Data(contentsOf: u) else { return nil }
        guard let e = try? JSONDecoder().decode(Entry.self, from: data), e.version == Self.version,
              now.timeIntervalSince(e.savedAt) < maxAge, e.savedAt <= now.addingTimeInterval(300) else {
            try? FileManager.default.removeItem(at: u)      // wrong version, expired or unreadable
            return nil
        }
        return (e.body, e.savedAt)
    }

    /// Removes expired and unreadable entries, then the oldest ones beyond `maxEntries`.
    func prune(now: Date = Date()) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        var live: [(URL, Date)] = []
        for f in files {
            guard f.pathExtension == "fc", let data = try? Data(contentsOf: f),
                  let e = try? JSONDecoder().decode(Entry.self, from: data),
                  e.version == Self.version, now.timeIntervalSince(e.savedAt) < maxAge else {
                try? fm.removeItem(at: f); continue
            }
            live.append((f, e.savedAt))
        }
        // Newest first; ties broken by name so the result never depends on directory order.
        live.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.lastPathComponent < $1.0.lastPathComponent }
        for (f, _) in live.dropFirst(maxEntries) { try? fm.removeItem(at: f) }
    }

    func removeAll() { try? FileManager.default.removeItem(at: directory) }

    /// Deletes cache files written by earlier versions (they had coordinates in their names).
    static func removeLegacyFiles() {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let files = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) else { return }
        for f in files where f.lastPathComponent.hasPrefix("forecast_") && f.pathExtension == "json" { try? fm.removeItem(at: f) }
    }
}
