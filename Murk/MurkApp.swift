import SwiftUI

@main
struct MurkApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var phase

    init() { BackgroundRefresh.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .task { await state.start() }
                .onChange(of: phase) { _, newPhase in
                    switch newPhase {
                    case .active: state.refreshIfStale()
                    case .background:
                        SoundEngine.shared.stop()
                        BackgroundRefresh.schedule()
                    default: break
                    }
                }
        }
    }
}
