import Foundation
import CoreLocation
import WidgetKit

/// The watch's own forecast: where you are (or the last place), from the same service as the iPhone app.
@MainActor
final class WatchModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var forecast: Forecast? = WatchStore.cached()
    @Published var loading = false
    @Published var problem: String?
    let unit = WatchStore.unit

    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<CLLocation?, Never>?
    private var lastRefresh: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh(force: Bool = false) async {
        if !force, let last = lastRefresh, Date().timeIntervalSince(last) < 10 * 60 { return }
        loading = true
        defer { loading = false }
        let place = await locate() ?? WatchStore.place
        do {
            forecast = try await WatchStore.fetch(place)
            problem = nil
            lastRefresh = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            if forecast == nil { problem = String(localized: "Couldn't load the forecast.") }
        }
    }

    // MARK: Location

    private func locate() async -> Place? {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: return nil
        default: break
        }
        let loc: CLLocation? = await withCheckedContinuation { c in
            pending?.resume(returning: nil)
            pending = c
            manager.requestLocation()
        }
        guard let loc else { return nil }
        let name = (try? await CLGeocoder().reverseGeocodeLocation(loc))?.first.flatMap { $0.locality ?? $0.name }
        // Rounded to about 1 km: the forecast doesn't need more.
        return Place(name: name ?? String(localized: "Here"),
                     latitude: Coordinate.rounded(loc.coordinate.latitude, places: 2),
                     longitude: Coordinate.rounded(loc.coordinate.longitude, places: 2),
                     isCurrentLocation: true)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in pending?.resume(returning: l); pending = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in pending?.resume(returning: nil); pending = nil }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            if s == .denied || s == .restricted { pending?.resume(returning: nil); pending = nil }
        }
    }
}
