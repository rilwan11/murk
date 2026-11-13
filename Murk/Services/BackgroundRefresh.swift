import Foundation
import BackgroundTasks
import WidgetKit

/// Checks for new weather alerts in the background (iOS decides exactly when, roughly every 30+ min).
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
            let place = SharedStore.place
            let d = UserDefaults.standard
            if (d.object(forKey: "alerts") as? Bool ?? true), let list = try? await WeatherService().alerts(for: place) {
                var seen = Set(d.stringArray(forKey: "seenAlerts") ?? [])
                let fresh = list.filter { !seen.contains($0.id) }
                if !fresh.isEmpty {
                    fresh.forEach { seen.insert($0.id) }
                    d.set(Array(seen.suffix(200)), forKey: "seenAlerts")
                    AppState.postNotifications(fresh, place: place)
                }
            }
            WidgetCenter.shared.reloadAllTimelines()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
