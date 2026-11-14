import Foundation

typealias HTTPFetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Why a forecast couldn't be loaded, in terms the screen can explain.
enum WeatherError: LocalizedError, Equatable {
    case offline
    case timedOut
    case provider(status: Int, reason: String?)
    case badData

    var errorDescription: String? {
        switch self {
        case .offline: return String(localized: "You're offline.")
        case .timedOut: return String(localized: "The forecast took too long.")
        case .provider: return String(localized: "The forecast service is unavailable.")
        case .badData: return String(localized: "The forecast came back incomplete.")
        }
    }
}

/// The optional parts of a forecast. They never hold up the main screen.
struct ForecastExtras: Equatable {
    var aqi: Int?
    var alerts: [WeatherAlert] = []
    /// False when the alert lookup failed, so the caller keeps what it had instead of clearing it.
    var alertsLoaded = false
}

protocol WeatherProviding {
    /// The last saved forecast for a place, marked as cached. Reads disk only.
    func cached(for place: Place) -> Forecast?
    /// Temperature, conditions and the days ahead. Throws `WeatherError` or `CancellationError`.
    func core(for place: Place) async throws -> Forecast
    /// Air quality and official alerts. Never throws; missing pieces come back empty.
    func extras(for place: Place) async -> ForecastExtras
}

/// All weather data access: requests, retry and timeout policy, parsing, and the disk cache.
struct WeatherRepository: WeatherProviding {
    /// A hook for usage and error monitoring. No coordinates or response bodies are passed.
    enum Event: Equatable {
        case request(kind: String, ok: Bool, milliseconds: Int)
        case retry(kind: String)
        case cacheHit
    }

    var config: ProviderConfig = .current
    var fetch: HTTPFetch = { try await URLSession.shared.data(for: $0) }
    var cache: ForecastCache? = .standard
    /// Decimal places kept in coordinates sent to providers.
    var coordinatePlaces: @Sendable () -> Int = { SharedStore.approximateLocation ? 1 : 2 }
    var onEvent: (@Sendable (Event) -> Void)?
    var firstTimeout: TimeInterval = 12
    var retryTimeout: TimeInterval = 20
    /// Widgets and background refreshes get one attempt only.
    var allowRetry = true

    static var live: WeatherProviding {
        #if DEBUG
        if let stub = DebugStubs.repository() { return stub }
        #endif
        return WeatherRepository()
    }

    func cached(for place: Place) -> Forecast? {
        guard let hit = cache?.load(for: place),
              let f = try? WeatherAPI.parseForecast(hit.body, place: place, fetchedAt: hit.savedAt, isCached: true) else { return nil }
        onEvent?(.cacheHit)
        return f
    }

    func core(for place: Place) async throws -> Forecast {
        let places = coordinatePlaces()
        var data: Data
        do {
            data = try await get(WeatherAPI.forecastURL(place, light: false, places: places, config: config), kind: "forecast", timeout: firstTimeout)
        } catch let e as WeatherError where e == .timedOut && allowRetry {
            // A slow network gets one more try with a smaller request. No retry when plainly offline.
            try Task.checkCancellation()
            onEvent?(.retry(kind: "forecast"))
            data = try await get(WeatherAPI.forecastURL(place, light: true, places: places, config: config), kind: "forecast", timeout: retryTimeout)
        }
        let now = Date()
        let forecast: Forecast
        do { forecast = try WeatherAPI.parseForecast(data, place: place, fetchedAt: now) } catch { throw WeatherError.badData }
        cache?.save(data, for: place, at: now)
        return forecast
    }

    func extras(for place: Place) async -> ForecastExtras {
        let places = coordinatePlaces()
        async let aqi: Int? = airQuality(for: place, places: places)
        async let alerts: [WeatherAlert]? = try? await self.alerts(for: place)
        let a = await alerts
        return ForecastExtras(aqi: await aqi, alerts: a ?? [], alertsLoaded: a != nil)
    }

    private func airQuality(for place: Place, places: Int) async -> Int? {
        guard let d = try? await get(WeatherAPI.airQualityURL(place, places: places, config: config), kind: "aqi", timeout: 8) else { return nil }
        return try? WeatherAPI.parseAQI(d)
    }

    /// Official alerts (US National Weather Service; empty elsewhere).
    func alerts(for place: Place) async throws -> [WeatherAlert] {
        var req = URLRequest(url: WeatherAPI.alertsURL(place, places: coordinatePlaces(), config: config))
        req.setValue("Murk weather app (github.com/rilwan11/murk)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        do {
            let data = try await get(req, kind: "alerts", timeout: 10)
            return (try? WeatherAPI.parseAlerts(data)) ?? []
        } catch WeatherError.provider(let status, _) where status == 404 || status == 400 {
            return []       // outside the area NWS covers
        }
    }

    // MARK: Transport

    private func get(_ url: URL, kind: String, timeout: TimeInterval) async throws -> Data {
        try await get(URLRequest(url: url), kind: kind, timeout: timeout)
    }

    private func get(_ request: URLRequest, kind: String, timeout: TimeInterval) async throws -> Data {
        var req = request
        req.timeoutInterval = timeout
        guard req.url?.scheme == "https" else { throw WeatherError.badData }    // providers are HTTPS-only
        let start = Date()
        func report(_ ok: Bool) { onEvent?(.request(kind: kind, ok: ok, milliseconds: Int(Date().timeIntervalSince(start) * 1000))) }
        do {
            let (data, resp) = try await fetch(req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                report(false)
                throw WeatherError.provider(status: code, reason: WeatherAPI.errorReason(data))
            }
            report(true)
            return data
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            report(false)
            switch e.code {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: throw WeatherError.offline
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: throw WeatherError.timedOut
            default: throw WeatherError.provider(status: e.code.rawValue, reason: nil)
            }
        }
    }
}
