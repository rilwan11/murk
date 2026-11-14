import SwiftUI

/// "WIND SPEED ............ 3 MPH" row, optionally highlighted as a white pill.
struct DetailRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let label: String
    let value: String
    var highlighted = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label).lineLimit(1).minimumScaleFactor(0.7)
            if highlighted { Spacer(minLength: 8) }
            else { Rectangle().fill(p.line).frame(height: 1).accessibilityHidden(true) }
            Text(value).lineLimit(1).minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
        .font(.mono(14))
        .tracking(1.5)
        .textCase(.uppercase)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .foregroundStyle(highlighted ? p.onInk : p.ink)
        .background(Capsule().fill(highlighted ? p.ink : .clear))
    }
    private var p: Palette { Palette(skin: state.skin, sky: sky) }
}

/// Large page title like "Air".
struct PageTitle: View {
    let text: String
    var body: some View {
        Text(text).font(.display(44)).tracking(-1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }
}

/// Small caption note in mono.
struct Note: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let text: String
    var body: some View {
        Text(text).font(.mono(10)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(Palette(skin: state.skin, sky: sky).muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10)
    }
}

/// Day weather icon using SF Symbols with weather-ish colors.
struct DayIcon: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let condition: Condition

    var body: some View {
        Image(systemName: condition.symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(primary, secondary)
            .font(.system(size: 22, weight: .semibold))
            .frame(height: 26)
    }
    private var primary: Color {
        switch condition.code {
        case 0, 1: return state.skin.sun
        default: return Palette(skin: state.skin, sky: sky).ink
        }
    }
    private var secondary: Color {
        switch condition.precip {
        case .rain: return state.skin.rain
        case .snow: return Palette(skin: state.skin, sky: sky).ink
        case .none: return condition.code == 2 ? state.skin.sun : Palette(skin: state.skin, sky: sky).ink
        }
    }
}

extension View {
    /// Standard padding for detail pages.
    func detailPage() -> some View {
        self.padding(.horizontal, 10).frame(maxWidth: 460)
    }
}

/// A frosted card that keeps text readable over the live sky.
struct GlassCard<Content: View>: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @ViewBuilder var content: Content
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        VStack(spacing: 2) { content }
            .padding(.vertical, 10).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(p.glass))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(p.line.opacity(0.6), lineWidth: 0.5))
    }
}

/// Official alerts in full: what, how serious, until when, and what to do.
struct AlertSheet: View {
    @Environment(\.dismiss) private var dismiss
    let alerts: [WeatherAlert]
    let place: String
    let time: (Date?) -> String

    var body: some View {
        NavigationStack {
            List(alerts) { a in
                VStack(alignment: .leading, spacing: 8) {
                    Label(a.event, systemImage: a.isSevere ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.headline)
                    Text("Severity: \(a.severity)").font(.subheadline.weight(.semibold))
                    if let ends = a.ends {
                        Text("Until \(ends.formatted(date: .abbreviated, time: .omitted)), \(time(ends))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(a.headline).font(.subheadline)
                    if let i = a.instruction, !i.isEmpty { Text(i).font(.footnote) }
                    if let d = a.detail, !d.isEmpty { Text(d).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 6)
            }
            .navigationTitle(Text("Alerts · \(place)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Text("Issued by the US National Weather Service. Murk checks for alerts when it refreshes, so there can be a delay. Follow local officials in an emergency.")
                        .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
