import SwiftUI

@main
struct MurkApp: App {
    @StateObject private var state = AppState()
    @StateObject private var store = EntitlementStore()
    @StateObject private var cloud = CloudSync()
    @Environment(\.scenePhase) private var phase

    /// Unit tests host the app; they drive their own state and must not start real work.
    private static let isUnitTesting = NSClassFromString("XCTestCase") != nil

    init() { BackgroundRefresh.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(store)
                .environmentObject(cloud)
                .task {
                    guard !Self.isUnitTesting else { return }
                    let s = state
                    store.onChange = { [weak s] pro in
                        s?.setPro(pro)
                        if !pro { AppIcon.revertIfPremium() }
                    }
                    if CloudSync.isAvailableInThisBuild {
                        cloud.onRemote = { [weak s] settings in s?.apply(settings) }
                        cloud.startObserving { [weak s] in s?.isPro ?? false }
                        cloud.pull(isPro: state.isPro)
                    }
                    store.start()
                    await state.migrateNotifications()
                    await state.start()
                }
                .onOpenURL { state.open($0) }
                .onChange(of: phase) { _, newPhase in
                    guard !Self.isUnitTesting else { return }
                    switch newPhase {
                    case .active:
                        SoundEngine.shared.resume()
                        state.refreshIfStale()
                        Task { await store.refresh() }
                        if CloudSync.isAvailableInThisBuild { cloud.pull(isPro: state.isPro) }
                    case .background:
                        SoundEngine.shared.stop()
                        BackgroundRefresh.schedule()
                    default: break
                    }
                }
        }
    }
}
