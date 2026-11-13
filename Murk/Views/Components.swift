import SwiftUI

/// "WIND SPEED ............ 3 MPH" row, optionally highlighted as a white pill.
struct DetailRow: View {
    @EnvironmentObject var state: AppState
    let label: String
    let value: String
    var highlighted = false

    var body: some View {
        HStack(spacing: 10) {
            Text(label).lineLimit(1)
            if highlighted { Spacer(minLength: 8) }
            else { Rectangle().fill(state.skin.line).frame(height: 1) }
            Text(value).lineLimit(1)
        }
        .font(.mono(14))
        .tracking(1.5)
        .textCase(.uppercase)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .foregroundStyle(highlighted ? state.skin.bg : state.skin.ink)
        .background(Capsule().fill(highlighted ? state.skin.ink : .clear))
    }
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
    let text: String
    var body: some View {
        Text(text).font(.mono(10)).tracking(1.2).textCase(.uppercase)
            .foregroundStyle(state.skin.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 10)
    }
}

/// Day weather icon using SF Symbols with weather-ish colors.
struct DayIcon: View {
    @EnvironmentObject var state: AppState
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
        default: return state.skin.ink
        }
    }
    private var secondary: Color {
        switch condition.precip {
        case .rain: return state.skin.rain
        case .snow: return state.skin.ink
        case .none: return condition.code == 2 ? state.skin.sun : state.skin.ink
        }
    }
}

extension View {
    /// Standard padding for detail pages.
    func detailPage() -> some View {
        self.padding(.horizontal, 10).frame(maxWidth: 460)
    }
}
