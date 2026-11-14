import Foundation
import BackgroundTasks
import WidgetKit

/// Refreshes the forecast in the background (iOS decides exactly when, roughly every 30+ min):
/// updates the widgets' snapshot and sends any new alerts the user asked for.
enum BackgroundRefresh {
    static let id = "com.rilwan11.murk.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handle(task)
        }
    }

    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: id)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            let ok = await refresh()
            task.setTaskCompleted(success: ok && !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// One bounded refresh for the place the widgets show.
    static func refresh(repository: WeatherProviding = WeatherRepository.live, defaults: UserDefaults = .standard) async -> Bool {
        let place = SharedStore.place
        guard var f = try? await repository.core(for: place), !Task.isCancelled else { return false }
        WidgetSnapshot(forecast: f, unit: SharedStore.unit, skin: SharedStore.skin).save()
        WidgetCenter.shared.reloadAllTimelines()

        let rules = NotificationRules.load(defaults)
        if rules.official || rules.anyAdvanced {
            let extras = await repository.extras(for: place)
            guard !Task.isCancelled else { return true }
            f.aqi = extras.aqi
            f.alerts = extras.alerts
            AlertDispatcher.deliver(for: f, rules: rules, unit: SharedStore.unit,
                                    isPro: defaults.bool(forKey: ProStatus.cacheKey))
        }
        return true
    }
}
