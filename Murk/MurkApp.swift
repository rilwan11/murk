import SwiftUI

@main
struct MurkApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .task { await state.start() }
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .active { state.refreshIfStale() }
                }
        }
    }
}
