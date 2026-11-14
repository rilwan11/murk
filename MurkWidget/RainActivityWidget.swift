import ActivityKit
import WidgetKit
import SwiftUI

/// The rain countdown on the Lock Screen and in the Dynamic Island.
struct RainActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RainActivityAttributes.self) { context in
            RainLockScreen(place: context.attributes.place, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "murk://rain"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label { Text(context.attributes.place).lineLimit(1) } icon: { Image(systemName: s.symbol) }
                        .font(.caption.weight(.semibold)).foregroundStyle(RainColors.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RainTimer(state: s, stale: context.isStale).font(.title3.weight(.black)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.isStale ? s.arrived : s.lead).font(.caption).foregroundStyle(.secondary)
                        RainBars(state: s).frame(height: 34)
                    }
                }
            } compactLeading: {
                Image(systemName: s.symbol).foregroundStyle(RainColors.accent)
            } compactTrailing: {
                RainTimer(state: s, stale: context.isStale).monospacedDigit().frame(maxWidth: 44).font(.caption.weight(.bold))
            } minimal: {
                Image(systemName: s.symbol).foregroundStyle(RainColors.accent)
            }
            .widgetURL(URL(string: "murk://rain"))
            .keylineTint(RainColors.accent)
        }
    }
}

enum RainColors {
    static let accent = Color(red: 0.44, green: 0.72, blue: 1.0)
}

/// "12:34" counting down, or "Now" once the moment has passed.
struct RainTimer: View {
    let state: RainCountdown
    let stale: Bool

    var body: some View {
        if stale || state.at <= Date() {
            Text("Now")
        } else {
            Text(timerInterval: Date()...state.at, countsDown: true, showsHours: false)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RainLockScreen: View {
    let place: String
    let state: RainCountdown
    let stale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Label(place, systemImage: state.symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(RainColors.accent).lineLimit(1)
                Text(stale ? state.arrived : state.lead).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                RainTimer(state: state, stale: stale)
                    .font(.system(size: 40, weight: .black)).monospacedDigit().foregroundStyle(.white)
            }
            .frame(width: 128, alignment: .leading)
            RainBars(state: state).frame(height: 64)
        }
        .padding(16)
    }
}

/// The next two hours in 15-minute bars, with the moment of change marked.
struct RainBars: View {
    let state: RainCountdown

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(state.levels.enumerated()), id: \.offset) { i, level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level > 0.02 ? RainColors.accent : Color.white.opacity(0.18))
                            .frame(height: max(3, g.size.height * CGFloat(level)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .accessibilityHidden(true)
                            .id(i)
                    }
                }
            }
            HStack {
                Text("Now")
                Spacer()
                Text(state.from.addingTimeInterval(Double(state.levels.count) * 900), style: .time)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}
