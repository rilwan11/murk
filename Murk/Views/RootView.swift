import SwiftUI

/// Reports the 3D stage's frame so page swipes that start on it are left to the scene.
struct NoSwipeZone: Equatable { let page: Int; let rect: CGRect }

struct StageFrameKey: PreferenceKey {
    static var defaultValue: [NoSwipeZone] = []
    static func reduce(value: inout [NoSwipeZone], nextValue: () -> [NoSwipeZone]) { value += nextValue() }
}

extension View {
    /// Marks this view's area as "don't page here" (the 3D scene, the day scrubber, the city header, the 3D moon).
    /// Frames are measured within their own page, which lines up with the screen when that page is showing.
    func noPageSwipe(page: Int) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: StageFrameKey.self, value: [NoSwipeZone(page: page, rect: g.frame(in: .named("page")))])
        })
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var store: EntitlementStore
    @Environment(\.scenePhase) private var phase
    @State private var page = 0
    @State private var drag: CGFloat = 0
    @State private var dragActive = false
    @State private var noSwipe: [NoSwipeZone] = []
    @State private var showSettings = false

    private let pageCount = 5

    var body: some View {
        let skin = state.skin
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottom) {
                skin.bg.ignoresSafeArea()
                // The other pages sit on the live sky too (the Now page draws its own, which follows the scrubber).
                TimelineView(.periodic(from: .now, by: 300)) { tl in
                    if let f = state.forecast, let sky = Sky.current(f, skin: skin, at: tl.date) {
                        SkyBackground(sky: sky).transition(.opacity)
                    }
                }

                HStack(spacing: 0) {
                    NowView(showSettings: $showSettings).frame(width: w).coordinateSpace(name: "page")
                        .environment(\.pageActive, live(0))
                        .accessibilityHidden(page != 0)
                    Group {
                        AirView().frame(width: w).coordinateSpace(name: "page").environment(\.pageActive, live(1)).accessibilityHidden(page != 1)
                        RainView().frame(width: w).coordinateSpace(name: "page").environment(\.pageActive, live(2)).accessibilityHidden(page != 2)
                        SunView().frame(width: w).coordinateSpace(name: "page").environment(\.pageActive, live(3)).accessibilityHidden(page != 3)
                        MoonView().frame(width: w).coordinateSpace(name: "page").environment(\.pageActive, live(4)).accessibilityHidden(page != 4)
                    }
                    .environment(\.sky, state.forecast.flatMap { Sky.current($0, skin: skin) })
                }
                .frame(width: w, alignment: .leading)
                .offset(x: -CGFloat(page) * w + drag)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: page)
                .simultaneousGesture(swipe(width: w))

                PageDots(count: pageCount, page: $page)
                    .environment(\.sky, page == 0 ? nil : state.forecast.flatMap { Sky.current($0, skin: skin) })
                    .padding(.bottom, 4)
            }
            .coordinateSpace(name: "root")
            .onPreferenceChange(StageFrameKey.self) { noSwipe = $0 }
        }
        .foregroundStyle(skin.ink)
        .preferredColorScheme(skin.isLight ? .light : .dark)
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(state).environmentObject(store)
        }
        // From Settings the paywall is presented by the settings sheet itself.
        .sheet(item: showSettings ? .constant(nil) : $state.paywall) { reason in
            PaywallView(reason: reason).environmentObject(store)
        }
        .onChange(of: state.route) { _, _ in follow() }
        .onAppear { follow() }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .animation(.easeInOut(duration: 0.4), value: skin)
    }

    /// Only the page on screen animates, and only while the app is in front.
    private func live(_ i: Int) -> Bool {
        phase == .active && !showSettings && abs(page - i) <= (dragActive ? 1 : 0)
    }

    /// Goes where a murk:// link points.
    private func follow() {
        guard let route = state.route else { return }
        state.route = nil
        switch route {
        case .page(let i):
            showSettings = false
            withAnimation { page = min(max(i, 0), pageCount - 1) }
        case .settings:
            showSettings = true
        }
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .named("root"))
            .onChanged { v in
                // Drags that begin on the 3D scene spin it instead of paging.
                if !dragActive && noSwipe.contains(where: { $0.page == page && $0.rect.contains(v.startLocation) }) { return }
                guard abs(v.translation.width) > abs(v.translation.height) || dragActive else { return }
                dragActive = true
                var t = v.translation.width
                if (page == 0 && t > 0) || (page == pageCount - 1 && t < 0) { t /= 3 }   // rubber band
                drag = t
            }
            .onEnded { v in
                guard dragActive else { return }
                dragActive = false
                let predicted = v.predictedEndTranslation.width
                var p = page
                if predicted < -width / 3 { p += 1 } else if predicted > width / 3 { p -= 1 }
                withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) {
                    page = min(max(p, 0), pageCount - 1)
                    drag = 0
                }
            }
    }
}

struct PageDots: View {
    static let names = [String(localized: "Now"), String(localized: "Air"), String(localized: "Rain"), String(localized: "Sun"), String(localized: "Moon")]
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let count: Int
    @Binding var page: Int

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky ?? (page == 0 ? state.forecast.flatMap { Sky.current($0, skin: state.skin) } : nil))
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? p.ink : p.muted.opacity(0.6))
                    .frame(width: i == page ? 16 : 6, height: 6)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { page = i } }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Page"))
        .accessibilityValue(Text(Self.names[min(page, Self.names.count - 1)]))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: page = min(page + 1, count - 1)
            case .decrement: page = max(page - 1, 0)
            @unknown default: break
            }
        }
        .padding(.horizontal, 10)
        .background(Capsule().fill(UIAccessibility.isReduceTransparencyEnabled ? AnyShapeStyle(p.glass) : AnyShapeStyle(.ultraThinMaterial)).opacity(page == 0 ? 0 : 1))
        .animation(.easeInOut(duration: 0.25), value: page)
    }
}
