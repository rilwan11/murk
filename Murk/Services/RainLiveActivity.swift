import Foundation
import ActivityKit

/// Starts, updates and ends the rain countdown on the Lock Screen and in the Dynamic Island.
@MainActor
enum RainLiveActivity {
    static func sync(_ forecast: Forecast?, enabled: Bool, now: Date = Date()) {
        let plan = enabled ? forecast.flatMap { RainCountdown.plan($0, now: now) } : nil
        let place = forecast?.place.name ?? ""
        let running = Activity<RainActivityAttributes>.activities
        Task {
            guard let plan, ActivityAuthorizationInfo().areActivitiesEnabled else {
                for a in running { await a.end(nil, dismissalPolicy: .immediate) }
                return
            }
            // Stale a few minutes after the moment, so an old countdown never lingers as if it were current.
            let content = ActivityContent(state: plan, staleDate: plan.at.addingTimeInterval(20 * 60))
            if let a = running.first(where: { $0.attributes.place == place }) {
                if a.content.state != plan { await a.update(content) }
                for other in running where other.id != a.id { await other.end(nil, dismissalPolicy: .immediate) }
            } else {
                for a in running { await a.end(nil, dismissalPolicy: .immediate) }
                // Only possible while Murk is open; background refreshes update an activity that's already running.
                _ = try? Activity.request(attributes: RainActivityAttributes(place: place), content: content, pushType: nil)
            }
        }
    }
}
