import SwiftUI

/// Reports the 3D stage's frame so page swipes that start on it are left to the scene.
struct StageFrameKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}

extension View {
    /// Marks this view's area as "don't page here" (the 3D scene, the day scrubber, the city header).
    func noPageSwipe() -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: StageFrameKey.self, value: [g.frame(in: .named("root"))])
        })
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @State private var page = 0
    @State private var drag: CGFloat = 0
    @State private var dragActive = false
    @State private var noSwipe: [CGRect] = []
    @State private var showSettings = false

    private let pageCount = 5

    var body: some View {
        let skin = state.skin
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .bottom) {
                skin.bg.ignoresSafeArea()

                HStack(spacing: 0) {
                    NowView(showSettings: $showSettings).frame(width: w)
                    AirView().frame(width: w)
                    RainView().frame(width: w)
                    SunView().frame(width: w)
                    MoonView().frame(width: w)
                }
                .frame(width: w, alignment: .leading)
                .offset(x: -CGFloat(page) * w + drag)
                .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.86), value: page)
                .simultaneousGesture(swipe(width: w))

                PageDots(count: pageCount, page: $page)
                    .padding(.bottom, 4)
            }
            .coordinateSpace(name: "root")
            .onPreferenceChange(StageFrameKey.self) { noSwipe = $0 }
        }
        .foregroundStyle(skin.ink)
        .preferredColorScheme(skin.isLight ? .light : .dark)
        .sheet(isPresented: $showSettings) {
            SettingsSheet().environmentObject(state)
        }
        .animation(.easeInOut(duration: 0.4), value: skin)
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .named("root"))
            .onChanged { v in
                // Drags that begin on the 3D scene spin it instead of paging.
                if page == 0 && noSwipe.contains(where: { $0.contains(v.startLocation) }) { return }
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
    @EnvironmentObject var state: AppState
    let count: Int
    @Binding var page: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == page ? state.skin.ink : state.skin.muted.opacity(0.6))
                    .frame(width: i == page ? 16 : 6, height: 6)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { page = i } }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: page)
    }
}
