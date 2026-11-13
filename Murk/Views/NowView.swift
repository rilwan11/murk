import SwiftUI
import UIKit

struct NowView: View {
    @EnvironmentObject var state: AppState
    @Binding var showSettings: Bool
    @State private var selectedDay = 0
    @State private var regen = 0
    @State private var reset = 0
    @State private var showHint = true

    var body: some View {
        let skin = state.skin
        VStack(spacing: 0) {
            header
            if let pill = state.headsUp {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                    Text(pill).font(.mono(12)).tracking(2)
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .foregroundStyle(skin.bg)
                .background(Capsule().fill(skin.ink))
                .padding(.top, 8)
                .transition(.opacity)
            }

            ZStack(alignment: .bottom) {
                if let config = sceneConfig {
                    WeatherSceneView(config: config)
                } else {
                    ProgressView().tint(skin.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack {
                    Spacer()
                    Text("DRAG TO SPIN · PINCH TO ZOOM · TAP FOR NEW CLOUDS")
                        .font(.mono(9)).tracking(1).foregroundStyle(skin.muted)
                        .opacity(showHint ? 1 : 0)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button { reset += 1 } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().stroke(skin.line))
                    }
                    .foregroundStyle(skin.ink)
                    .padding(.trailing, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GeometryReader { g in
                Color.clear.preference(key: StageFrameKey.self, value: g.frame(in: .named("root")))
            })
            .task { try? await Task.sleep(for: .seconds(6)); withAnimation { showHint = false } }

            Text(conditionTitle)
                .font(.display(36)).tracking(-1)
                .minimumScaleFactor(0.6).lineLimit(1)
                .padding(.top, 6).padding(.horizontal, 20)

            if !state.minimal {
                ForecastStrip(selected: $selectedDay)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            footer
        }
        .padding(.bottom, 30)
        .animation(.easeInOut(duration: 0.3), value: state.minimal)
        .onChange(of: state.forecast?.place.id) { _, _ in selectedDay = 0 }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer()
            Button { showSettings = true } label: {
                HStack(spacing: 6) {
                    if state.forecast?.place.isCurrentLocation == true {
                        Image(systemName: "location.fill").font(.system(size: 13, weight: .bold))
                    }
                    Text(state.forecast?.place.name ?? state.activePlace?.name ?? "Murk")
                        .font(.system(size: 24, weight: .heavy)).lineLimit(1)
                }
            }
            .foregroundStyle(state.skin.ink)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 22, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(state.skin.ink)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private var footer: some View {
        Group {
            if let err = state.errorMessage {
                Button { state.retry() } label: { Text(err.uppercased()) }
                    .foregroundStyle(state.skin.sun)
            } else if let f = state.forecast {
                let day = selectedDay < f.daily.count ? f.daily[selectedDay] : nil
                if selectedDay > 0, let day {
                    Text("\(state.dayLabel(day, index: selectedDay)) HIGH · \(day.precipChance)% RAIN · TAP TODAY TO RETURN")
                } else {
                    Text("UPDATED \(state.time(f.fetchedAt)) · FORECAST BY OPEN-METEO")
                }
            } else if state.isLoading {
                Text("LOADING…")
            }
        }
        .font(.mono(9)).tracking(1.2)
        .foregroundStyle(state.skin.muted)
        .multilineTextAlignment(.center)
        .padding(.top, 12).padding(.horizontal, 20)
    }

    // MARK: Derived

    private var conditionTitle: String {
        guard let f = state.forecast else { return state.isLoading ? " " : "—" }
        if selectedDay > 0, selectedDay < f.daily.count { return f.daily[selectedDay].condition.title }
        return f.current.condition.title
    }

    private var sceneConfig: SceneConfig? {
        guard let f = state.forecast else { return nil }
        let today = selectedDay == 0
        let day = f.daily.indices.contains(selectedDay) ? f.daily[selectedDay] : nil
        let cond = today ? f.current.condition : (day?.condition ?? f.current.condition)
        let temp = today ? f.current.temperature : (day?.high ?? f.current.temperature)
        let sunUp = Astronomy.sunAltitude(latitude: f.place.latitude, longitude: f.place.longitude) > -2
        return SceneConfig(
            temperature: String(state.unit.temp(temp)),
            cover: cond.cloudCover,
            precip: today ? cond.precip : ((day?.precipChance ?? 0) >= 40 && cond.precip == .none ? .rain : cond.precip),
            intensity: today ? cond.intensity : (day.map { $0.precipChance >= 40 ? max(cond.intensity, Double($0.precipChance) / 100) : cond.intensity * 0.5 } ?? 0),
            isDay: today ? f.current.isDay || sunUp : true,
            moonAge: (Astronomy.moonAge() * 4).rounded() / 4,
            skin: state.skin,
            regenToken: regen,
            resetToken: reset)
    }
}

struct ForecastStrip: View {
    @EnvironmentObject var state: AppState
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                VStack(spacing: 4) {
                    Text(state.dayLabel(d, index: i)).font(.mono(11)).tracking(0.5)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    DayIcon(condition: d.condition)
                    Text("\(state.unit.temp(d.high))").font(.system(size: 19, weight: .heavy))
                    Text("\(state.unit.temp(d.low))").font(.system(size: 19, weight: .heavy))
                        .foregroundStyle(state.skin.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14).fill(state.skin.ink.opacity(i == selected ? 0.12 : 0)))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = i }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
