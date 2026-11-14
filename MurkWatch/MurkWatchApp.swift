import SwiftUI
import WidgetKit

@main
struct MurkWatchApp: App {
    @StateObject private var model = WatchModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environmentObject(model)
                .task { await model.refresh() }
                .onChange(of: phase) { _, p in if p == .active { Task { await model.refresh() } } }
        }
    }
}
