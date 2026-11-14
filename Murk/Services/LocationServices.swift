import Foundation
import CoreLocation
import MapKit

// MARK: - Waiting safely

/// Resumes a continuation exactly once, whichever of result, timeout or cancellation gets there first.
final class OneShot<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var cleanup: (() -> Void)?

    init(_ c: CheckedContinuation<T, Error>) { continuation = c }

    func onFinish(_ work: @escaping () -> Void) {
        lock.lock()
        if continuation == nil { lock.unlock(); work(); return }
        cleanup = work
        lock.unlock()
    }

    /// Returns false if something else already finished the wait.
    @discardableResult
    func resume(with result: Result<T, Error>) -> Bool {
        lock.lock()
        guard let c = continuation else { lock.unlock(); return false }
        continuation = nil
        let done = cleanup; cleanup = nil
        lock.unlock()
        done?()
        c.resume(with: result)
        return true
    }

    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return continuation == nil }
}

private final class OneShotSlot<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var shot: OneShot<T>?
    func set(_ s: OneShot<T>) { lock.lock(); shot = s; lock.unlock() }
    func get() -> OneShot<T>? { lock.lock(); defer { lock.unlock() }; return shot }
}

enum Deadline {
    struct TimedOut: Error {}

    /// Runs a callback-style operation with a time limit. `start` receives a handle to resume with the
    /// result; if the limit passes or the task is cancelled first, the wait ends with an error instead.
    static func run<T>(seconds: TimeInterval, start: @escaping (OneShot<T>) -> Void) async throws -> T {
        let slot = OneShotSlot<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
                let shot = OneShot(c)
                slot.set(shot)
                if Task.isCancelled { shot.resume(with: .failure(CancellationError())); return }
                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                    if !Task.isCancelled { shot.resume(with: .failure(TimedOut())) }
                }
                shot.onFinish { timer.cancel() }
                start(shot)
            }
        } onCancel: {
            slot.get()?.resume(with: .failure(CancellationError()))
        }
    }
}

// MARK: - Current location

enum LocationError: LocalizedError, Equatable {
    case denied
    case timedOut
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return String(localized: "Location is off for Murk. Turn it on in Settings, or pick a city.")
        case .timedOut: return String(localized: "Finding your location took too long.")
        case .unavailable: return String(localized: "Your location isn't available right now.")
        }
    }
}

protocol LocationProviding: AnyObject {
    /// Denied or restricted: the system will not prompt again.
    var isDenied: Bool { get }
    /// Already allowed, so no prompt will appear.
    var isAuthorized: Bool { get }
    /// Asks for permission if needed, then finds the device. Throws `LocationError` or `CancellationError`.
    func currentPlace() async throws -> Place
}

final class LocationManager: NSObject, CLLocationManagerDelegate, LocationProviding {
    private let manager = CLLocationManager()
    private var locationWait: OneShot<CLLocation>?
    private var authWait: OneShot<Void>?
    private var inFlight: Task<Place, Error>?

    /// How long to wait for a fix, a permission answer, and a place name.
    var fixTimeout: TimeInterval = 10
    var permissionTimeout: TimeInterval = 120
    var nameTimeout: TimeInterval = 5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    var isAuthorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedWhenInUse || s == .authorizedAlways
    }

    /// Concurrent callers share one request, so a second call never strands the first.
    @MainActor
    func currentPlace() async throws -> Place {
        if let t = inFlight { return try await t.value }
        let t = Task { @MainActor in try await self.fetchPlace() }
        inFlight = t
        defer { inFlight = nil }
        return try await withTaskCancellationHandler { try await t.value } onCancel: { t.cancel() }
    }

    @MainActor
    private func fetchPlace() async throws -> Place {
        if manager.authorizationStatus == .notDetermined {
            // Only "When In Use" is ever requested.
            _ = try? await Deadline.run(seconds: permissionTimeout) { (shot: OneShot<Void>) in
                self.authWait?.resume(with: .failure(CancellationError()))
                self.authWait = shot
                self.manager.requestWhenInUseAuthorization()
            }
            authWait = nil
            try Task.checkCancellation()
        }
        guard isAuthorized else { throw isDenied ? LocationError.denied : LocationError.unavailable }

        let location: CLLocation
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -600 {
            location = recent
        } else {
            do {
                location = try await Deadline.run(seconds: fixTimeout) { (shot: OneShot<CLLocation>) in
                    self.locationWait?.resume(with: .failure(CancellationError()))
                    self.locationWait = shot
                    self.manager.requestLocation()
                }
            } catch is Deadline.TimedOut {
                locationWait = nil
                manager.stopUpdatingLocation()
                // An older fix beats nothing.
                if let last = manager.location { location = last } else { throw LocationError.timedOut }
            } catch is CancellationError {
                locationWait = nil
                manager.stopUpdatingLocation()
                throw CancellationError()
            } catch {
                locationWait = nil
                throw isDenied ? LocationError.denied : LocationError.unavailable
            }
            locationWait = nil
        }

        var name = String(localized: "My Location")
        let geocoder = CLGeocoder()
        let mark: CLPlacemark? = try? await Deadline.run(seconds: nameTimeout) { (shot: OneShot<CLPlacemark?>) in
            shot.onFinish { geocoder.cancelGeocode() }
            geocoder.reverseGeocodeLocation(location) { marks, _ in shot.resume(with: .success(marks?.first)) }
        }
        try Task.checkCancellation()
        if let mark { name = mark.locality ?? mark.subAdministrativeArea ?? mark.name ?? name }
        return Place(name: name, latitude: location.coordinate.latitude,
                     longitude: location.coordinate.longitude, isCurrentLocation: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        authWait?.resume(with: .success(()))
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        locationWait?.resume(with: .success(loc))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationWait?.resume(with: .failure(error))
    }
}

// MARK: - City search

final class CitySearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            if query.trimmingCharacters(in: .whitespaces).isEmpty { results = [] }
            else { completer.queryFragment = query }
        }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = Array(completer.results.prefix(12))
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> Place? {
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        let coord = item.placemark.coordinate
        let name = completion.title.components(separatedBy: ",").first ?? completion.title
        return Place(name: name, latitude: coord.latitude, longitude: coord.longitude)
    }
}
