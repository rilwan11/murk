import SwiftUI

/// The frame every detail page shares: city and page name, a 3D hero, the big answer,
/// the shared hour slider, up to three picture cards, and the remaining rows tucked into Details.
struct PageScaffold<Hero: View, Extra: View, Cards: View, Details: View>: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let title: String
    let page: Int
    let verdict: Verdict?
    var showsSlider = true
    @ViewBuilder var hero: Hero
    /// Anything that belongs right under the answer (the Rain page's next-3-hours strip, the Moon's day slider).
    @ViewBuilder var extra: Extra
    @ViewBuilder var cards: Cards
    @ViewBuilder var details: Details
    @State private var showDetails = false

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                PageHeader(title: title)
                hero
                    .containerRelativeFrame(.vertical) { h, _ in h * 0.4 }
                    .noPageSwipe(page: page)
                    .scrollTransition(.interactive, axis: .vertical) { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0.35).scaleEffect(phase.isIdentity ? 1 : 0.88, anchor: .top)
                    }
                if let verdict { AnswerBlock(verdict: verdict) }
                extra
                if showsSlider, !state.upcomingHours.isEmpty {
                    HourScrubber(hours: state.upcomingHours, selection: $state.selectedHour)
                        .padding(.horizontal, 22)
                        .noPageSwipe(page: page)
                }
                VStack(spacing: 12) { cards }.detailPage()
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showDetails.toggle() }
                    } label: {
                        HStack {
                            Text("DETAILS").font(.mono(11)).tracking(1.5)
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                                .rotationEffect(.degrees(showDetails ? 180 : 0))
                        }
                        .foregroundStyle(p.muted)
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(showDetails ? "Hide details" : "Show details"))
                    if showDetails {
                        GlassCard { details }.transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .detailPage()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 90)
        }
        .foregroundStyle(p.ink)
    }
}

/// City name and page name, like the Now page's header.
struct PageHeader: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let title: String
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                if state.forecast?.place.isCurrentLocation == true {
                    Image(systemName: "location.fill").font(.system(size: 12, weight: .bold))
                }
                Text(state.forecast?.place.name ?? state.activePlace?.name ?? "Murk")
                    .font(.system(size: 20, weight: .heavy)).lineLimit(1)
            }
            Text(title.uppercased()).font(.mono(11)).tracking(2).foregroundStyle(p.muted)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The big answer in the Now page's type, and one plain sentence under it.
struct AnswerBlock: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let verdict: Verdict
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verdict.big)
                    .font(.system(size: 64, weight: .black).width(.compressed))
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .contentTransition(.numericText())
                if !verdict.unit.isEmpty {
                    Text(verdict.unit).font(.mono(13, .semibold)).tracking(1).foregroundStyle(p.muted)
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
            }
            Text(verdict.line)
                .font(.system(size: 17, weight: .semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
        }
        .animation(.easeInOut(duration: 0.25), value: verdict)
        .accessibilityElement(children: .combine)
    }
}

/// A card's small title line.
struct CardTitle: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let text: String
    var trailing: String? = nil
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        HStack {
            Text(text.uppercased()).font(.mono(11)).tracking(1.5)
            Spacer()
            if let trailing { Text(trailing).font(.mono(11)) }
        }
        .foregroundStyle(p.muted)
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Named tabs with icons in place of the dots; the current one is filled.
struct PageTabs: View {
    static let names = [String(localized: "Now"), String(localized: "Air"), String(localized: "Rain"), String(localized: "Sun"), String(localized: "Moon")]
    static let icons = ["cloud.sun.fill", "wind", "cloud.rain.fill", "sun.max.fill", "moon.fill"]
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Binding var page: Int

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky ?? state.forecast.flatMap { Sky.current($0, skin: state.skin) })
        HStack(spacing: 2) {
            ForEach(0..<Self.names.count, id: \.self) { i in
                let on = i == page
                Button {
                    withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.86)) { page = i }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: Self.icons[i]).font(.system(size: 13, weight: .semibold))
                        if on { Text(Self.names[i]).font(.system(size: 13, weight: .bold)).lineLimit(1) }
                    }
                    .foregroundStyle(on ? p.onInk : p.ink.opacity(0.8))
                    .padding(.horizontal, on ? 12 : 10).padding(.vertical, 8)
                    .background(Capsule().fill(on ? p.ink : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Self.names[i]))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(UIAccessibility.isReduceTransparencyEnabled ? AnyShapeStyle(p.glass) : AnyShapeStyle(.ultraThinMaterial)))
        .overlay(Capsule().stroke(p.line, lineWidth: 0.5))
        .animation(.easeInOut(duration: 0.25), value: page)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Pages"))
    }
}

/// The forecast hour the slider is on, or nil for now.
extension AppState {
    var selectedHourPoint: HourlyPoint? {
        guard let i = selectedHour, upcomingHours.indices.contains(i), i > 0 else { return nil }
        return upcomingHours[i]
    }
    /// The moment the pages are showing.
    var selectedMoment: Date { selectedHourPoint?.time ?? Date() }
}
