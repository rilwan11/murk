import Foundation

/// What iCloud sync carries: saved cities and preferences. Never the current location,
/// the selected city, or any history of where the user has been.
struct SyncedSettings: Codable, Equatable {
    var places: [Place]
    var unit: String
    var skin: String
    var autoSkin: Bool
    var minimal: Bool
    var headsUp: Bool
    var sound: Bool
    var rules: NotificationRules
}

struct SyncEnvelope: Codable {
    var version = 1
    var modifiedAt: Date
    var settings: SyncedSettings
}

/// The slice of iCloud key-value storage Murk uses. `NSUbiquitousKeyValueStore` already has these.
protocol CloudKeyValueStore: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}

/// Keeps saved cities and preferences the same across the user's devices, in their own private iCloud.
/// A Murk Pro feature, off until switched on, and the app works the same without it.
/// Newest change wins.
@MainActor
final class CloudSync: ObservableObject {
    static let key = "murk.settings.v1"

    /// Sync needs the iCloud key-value entitlement, which needs the paid developer program.
    /// Builds without it hide the feature (`MURK_ICLOUD_SYNC` build setting).
    static var isAvailableInThisBuild: Bool {
        let v = Bundle.main.object(forInfoDictionaryKey: "MurkCloudSync")
        if let b = v as? Bool { return b }
        return ["yes", "true", "1"].contains((v as? String ?? "").lowercased())
    }

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "cloud.enabled") } }
    @Published private(set) var lastSynced: Date?

    /// Called with settings that arrived from another device.
    var onRemote: ((SyncedSettings) -> Void)?

    private let store: CloudKeyValueStore
    private let defaults: UserDefaults
    private let now: () -> Date
    private var lastSeen: SyncedSettings?
    private var observer: NSObjectProtocol?
    private var localModifiedAt: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: "cloud.modifiedAt")) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "cloud.modifiedAt") }
    }

    init(store: CloudKeyValueStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.defaults = defaults
        self.now = now
        enabled = defaults.bool(forKey: "cloud.enabled")
    }

    private static func encoder() -> JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; return e }
    private static func decoder() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }

    /// Sends this device's settings up, if they changed.
    func push(_ settings: SyncedSettings, isPro: Bool) {
        guard enabled, isPro, settings != lastSeen else { return }
        let stamp = now()
        guard let data = try? Self.encoder().encode(SyncEnvelope(modifiedAt: stamp, settings: settings)) else { return }
        store.set(data, forKey: Self.key)
        store.synchronize()
        lastSeen = settings
        localModifiedAt = stamp
        lastSynced = stamp
    }

    /// Takes newer settings from iCloud, if there are any.
    func pull(isPro: Bool) {
        guard enabled, isPro, let data = store.data(forKey: Self.key),
              let envelope = try? Self.decoder().decode(SyncEnvelope.self, from: data), envelope.version == 1 else { return }
        guard envelope.modifiedAt > localModifiedAt, envelope.settings != lastSeen else { return }
        lastSeen = envelope.settings
        localModifiedAt = envelope.modifiedAt
        lastSynced = envelope.modifiedAt
        onRemote?(envelope.settings)
    }

    /// Turning sync on: take what's in iCloud if it's there, otherwise start it from this device.
    func turnOn(current: SyncedSettings, isPro: Bool) {
        enabled = true
        localModifiedAt = .distantPast
        lastSeen = nil
        pull(isPro: isPro)
        if lastSeen == nil { push(current, isPro: isPro) }
    }

    /// Removes Murk's data from iCloud. This device keeps its own settings, and sync is switched off.
    func reset() {
        store.removeObject(forKey: Self.key)
        store.synchronize()
        lastSeen = nil
        lastSynced = nil
        localModifiedAt = .distantPast
        enabled = false
    }

    /// Listens for changes made on other devices.
    func startObserving(isPro: @escaping () -> Bool) {
        guard observer == nil, let real = store as? NSUbiquitousKeyValueStore else { return }
        observer = NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                                          object: real, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pull(isPro: isPro()) }
        }
        real.synchronize()
    }
}
