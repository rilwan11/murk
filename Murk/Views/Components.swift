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
            Text(label).lineLimit(1)
            if highlighted { Spacer(minLength: 8) }
            else { Rectangle().fill(p.line).frame(height: 1) }
            Text(value).lineLimit(1)
        }
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
