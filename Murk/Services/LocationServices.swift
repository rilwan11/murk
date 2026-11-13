import Foundation
import CoreLocation
import MapKit

// MARK: - Current location

final class LocationManager: NSObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied
        var errorDescription: String? { "Location is off for Murk. Turn it on in Settings, or pick a city." }
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    private var inFlight: Task<Place, Error>?

    /// Concurrent callers share one request, so a second call never strands the first.
    func currentPlace() async throws -> Place {
        if let t = inFlight { return try await t.value }
        let t = Task { @MainActor in try await self.fetchPlace() }
        inFlight = t
        defer { inFlight = nil }
        return try await t.value
    }

    @MainActor
    private func fetchPlace() async throws -> Place {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                if let old = authContinuation { old.resume() }
                authContinuation = c
                manager.requestWhenInUseAuthorization()
            }
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { throw LocationError.denied }

        let location: CLLocation
        if let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -600 {
            location = recent
        } else {
            location = try await withCheckedThrowingContinuation { c in
                locationContinuation?.resume(throwing: CancellationError())
                locationContinuation = c
                manager.requestLocation()
            }
        }
        var name = "My Location"
        if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            name = mark.locality ?? mark.subAdministrativeArea ?? mark.name ?? name
        }
        return Place(name: name, latitude: location.coordinate.latitude,
                     longitude: location.coordinate.longitude, isCurrentLocation: true)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        authContinuation?.resume()
        authContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        locationContinuation?.resume(returning: loc)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
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
