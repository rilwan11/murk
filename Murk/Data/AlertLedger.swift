import Foundation

/// Remembers which notifications have already been sent, so the same alert never fires twice.
/// Entries carry the time they were first seen, expire after a fixed period, and are trimmed
/// oldest-first. The app and its background refresh share this one implementation.
struct AlertLedger {
    static let storageKey = "seenAlerts.v2"
    private static let legacyKey = "seenAlerts"
    private static let lock = NSLock()

    var defaults: UserDefaults = .standard
    var lifetime: TimeInterval = 14 * 86_400
    var capacity = 500

    /// Returns the IDs not seen before for this scope (a place), and records them, in one step.
    func claim(_ ids: [String], scope: String, now: Date = Date()) -> [String] {
        Self.lock.lock(); defer { Self.lock.unlock() }
        var seen = load(now: now)
        var fresh: [String] = []
        for id in ids {
            let key = "\(scope)|\(id)"
            if seen[key] != nil || seen["*|\(id)"] != nil || fresh.contains(id) { continue }
            seen[key] = now.timeIntervalSince1970
            fresh.append(id)
        }
        if !fresh.isEmpty { store(seen) }
        return fresh
    }

    func contains(_ id: String, scope: String, now: Date = Date()) -> Bool {
        Self.lock.lock(); defer { Self.lock.unlock() }
        let seen = load(now: now)
        return seen["\(scope)|\(id)"] != nil || seen["*|\(id)"] != nil
    }

    var count: Int {
        Self.lock.lock(); defer { Self.lock.unlock() }
        return (defaults.dictionary(forKey: Self.storageKey) ?? [:]).count
    }

    private func load(now: Date) -> [String: Double] {
        var seen = (defaults.dictionary(forKey: Self.storageKey) as? [String: Double]) ?? [:]
        // Carry over IDs remembered by the previous format; they applied to every place.
        if let old = defaults.stringArray(forKey: Self.legacyKey) {
            for id in old where seen["*|\(id)"] == nil { seen["*|\(id)"] = now.timeIntervalSince1970 }
            defaults.removeObject(forKey: Self.legacyKey)
        }
        let cutoff = now.timeIntervalSince1970 - lifetime
        return seen.filter { $0.value >= cutoff }
    }

    private func store(_ seen: [String: Double]) {
        var kept = seen
        if kept.count > capacity {
            // Oldest first; equal times fall back to the key, so trimming is always the same.
            let ordered = kept.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }
            for (k, _) in ordered.prefix(kept.count - capacity) { kept.removeValue(forKey: k) }
        }
        defaults.set(kept, forKey: Self.storageKey)
    }
}
