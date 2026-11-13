import SwiftUI
import UIKit

struct NowView: View {
    @EnvironmentObject var state: AppState
    @Binding var showSettings: Bool
    @State private var selectedDay = 0
    @State private var hour: Int? = nil          // index into upcoming hours while scrubbing
    @State private var regen = 0
    @State private var reset = 0
    @State private var showHint = true
    @State private var headerDrag: CGFloat = 0

    var body: some View {
        let skin = state.skin
        let config = sceneConfig
        VStack(spacing: 0) {
            header
            if let pill = state.headsUp {
                let isAlert = state.forecast?.alerts.isEmpty == false
                HStack(spacing: 8) {
                    Image(systemName: isAlert ? "exclamationmark.triangle.fill" : "cloud.rain.fill").font(.system(size: 12))
                    Text(pill).font(.mono(12)).tracking(2).lineLimit(1)
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .foregroundStyle(isAlert ? Color.white : skin.bg)
                .background(Capsule().fill(isAlert ? Color(hex: 0xD93A2B) : skin.ink))
                .padding(.top, 8)
                .transition(.opacity)
            }

            ZStack(alignment: .bottom) {
                if let config {
                    WeatherSceneView(config: config, onThunder: { SoundEngine.shared.thunder() })
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
                    Button { reset += 1; UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
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
            .noPageSwipe()
            .task { try? await Task.sleep(for: .seconds(6)); withAnimation { showHint = false } }

            Text(conditionTitle)
                .font(.display(36)).tracking(-1)
                .minimumScaleFactor(0.6).lineLimit(1)
                .padding(.top, 6).padding(.horizontal, 20)
            if let feels = feelsLike {
                Text("FEELS LIKE \(feels)°").font(.mono(10)).tracking(1.5).foregroundStyle(skin.muted)
                    .padding(.top, 2)
            }

            if !state.upcomingHours.isEmpty {
                HourScrubber(hours: state.upcomingHours, selection: $hour)
                    .padding(.top, 10).padding(.horizontal, 22)
                    .noPageSwipe()
            }

            if !state.minimal {
                ForecastStrip(selected: $selectedDay)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            footer
        }
        .padding(.bottom, 30)
        .animation(.easeInOut(duration: 0.3), value: state.minimal)
        .onChange(of: state.forecast?.place.id) { _, _ in selectedDay = 0; hour = nil }
        .onChange(of: selectedDay) { _, d in if d > 0 { hour = nil } }
        .onChange(of: hour) { _, h in if h != nil { selectedDay = 0 } }
        .onChange(of: soundKey) { _, _ in updateSound(config) }
        .onAppear { updateSound(config) }
    }

    // MARK: Pieces

    private var header: some View {
        let count = state.cityIDs.count
        return VStack(spacing: 4) {
            HStack {
                Button { state.cycleCity(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold)).frame(width: 44, height: 44)
                }
                .opacity(count > 1 ? 0.6 : 0).disabled(count < 2)
                Spacer()
                Button { showSettings = true } label: {
                    HStack(spacing: 6) {
                        if state.forecast?.place.isCurrentLocation == true {
                            Image(systemName: "location.fill").font(.system(size: 13, weight: .bold))
                        }
                        Text(state.forecast?.place.name ?? state.activePlace?.name ?? "Murk")
                            .font(.system(size: 24, weight: .heavy)).lineLimit(1)
                    }
                    .offset(x: headerDrag * 0.4)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 22, weight: .bold))
                        .frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(state.skin.ink)
            if count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle().fill(state.skin.ink.opacity(i == state.cityIndex ? 0.9 : 0.25)).frame(width: 5, height: 5)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20)
            .onChanged { headerDrag = $0.translation.width }
            .onEnded { v in
                withAnimation(.spring(response: 0.3)) { headerDrag = 0 }
                if v.translation.width < -50 { state.cycleCity(1) } else if v.translation.width > 50 { state.cycleCity(-1) }
            })
        .noPageSwipe()
    }

    private var footer: some View {
        Group {
            if let err = state.errorMessage {
                Button { state.retry() } label: { Text(err.uppercased()) }
                    .foregroundStyle(state.skin.sun)
            } else if let f = state.forecast {
                let day = selectedDay < f.daily.count ? f.daily[selectedDay] : nil
                if let h = hourPoint {
                    Text("\(hourLabel(h.time)) · \(h.precipChance)% RAIN · TAP NOW TO RETURN")
                } else if selectedDay > 0, let day {
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

    private var hourPoint: HourlyPoint? {
        guard let i = hour, state.upcomingHours.indices.contains(i), i > 0 else { return nil }
        return state.upcomingHours[i]
    }

    private func hourLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = state.forecast?.timeZone; f.dateFormat = "h a"
        return f.string(from: d).uppercased()
    }

    private var conditionTitle: String {
        guard let f = state.forecast else { return state.isLoading ? " " : "—" }
        if let h = hourPoint { return h.condition.title }
        if selectedDay > 0, selectedDay < f.daily.count { return f.daily[selectedDay].condition.title }
        return f.current.condition.title
    }

    private var feelsLike: Int? {
        guard let f = state.forecast, selectedDay == 0 else { return nil }
        if let h = hourPoint { return h.apparent.map(state.unit.temp) }
        return f.current.apparent.map(state.unit.temp)
    }

    private var sceneConfig: SceneConfig? {
        guard let f = state.forecast else { return nil }
        let lat = f.place.latitude, lon = f.place.longitude
        let today = selectedDay == 0
        let day = f.daily.indices.contains(selectedDay) ? f.daily[selectedDay] : nil

        var cond: Condition, temp: Double, isDay: Bool, wind: Double, dir: Double, alt: Double
        var precip: Precip, intensity: Double
        if let h = hourPoint {
            cond = h.condition; temp = h.temperature; isDay = h.isDay
            wind = h.windSpeed; dir = h.windDirection
            alt = Astronomy.sunAltitude(latitude: lat, longitude: lon, at: h.time)
            precip = cond.precip == .none && h.precipChance >= 50 ? .rain : cond.precip
            intensity = cond.intensity > 0 ? cond.intensity : (h.precip > 0.1 ? min(1, h.precip / 3) : (precip == .none ? 0 : 0.3))
        } else if today {
            cond = f.current.condition; temp = f.current.temperature
            alt = Astronomy.sunAltitude(latitude: lat, longitude: lon)
            isDay = f.current.isDay || alt > -2
            wind = f.current.windSpeed ?? 0; dir = f.current.windDirection ?? 0
            precip = cond.precip; intensity = cond.intensity
        } else {
            cond = day?.condition ?? f.current.condition; temp = day?.high ?? f.current.temperature
            isDay = true; alt = 45
            wind = day?.windMax ?? 0; dir = f.current.windDirection ?? 0
            let chance = day?.precipChance ?? 0
            precip = chance >= 40 && cond.precip == .none ? .rain : cond.precip
            intensity = chance >= 40 ? max(cond.intensity, Double(chance) / 100) : cond.intensity * 0.5
        }
        return SceneConfig(
            temperature: String(state.unit.temp(temp)),
            cover: cond.cloudCover,
            precip: precip,
            intensity: intensity,
            isDay: isDay,
            moonAge: (Astronomy.moonAge() * 4).rounded() / 4,
            skin: state.skin,
            windSpeed: (wind / 5).rounded() * 5,
            windDirection: (dir / 15).rounded() * 15,
            thunder: (95...99).contains(cond.code),
            sunAltitude: (alt / 2).rounded() * 2,
            regenToken: regen,
            resetToken: reset)
    }

    private var soundKey: String {
        guard let c = sceneConfig else { return "" }
        return "\(c.precip)-\(c.intensity)-\(c.windSpeed)-\(state.sound)"
    }

    private func updateSound(_ c: SceneConfig?) {
        guard let c, state.sound else { SoundEngine.shared.set(rain: 0, wind: 0); return }
        let rain = c.precip == .rain ? max(0.25, c.intensity) : 0
        SoundEngine.shared.set(rain: rain, wind: min(1, c.windSpeed / 50))
    }
}

/// Drag across the next 24 hours to play the weather forward.
struct HourScrubber: View {
    @EnvironmentObject var state: AppState
    let hours: [HourlyPoint]
    @Binding var selection: Int?

    var body: some View {
        GeometryReader { g in
            let n = max(1, hours.count - 1)
            let i = selection ?? 0
            let x = g.size.width * CGFloat(i) / CGFloat(n)
            ZStack(alignment: .leading) {
                Capsule().fill(state.skin.line).frame(height: 6)
                Capsule().fill(state.skin.ink.opacity(0.85)).frame(width: max(6, x), height: 6)
                ForEach(Array(stride(from: 0, through: n, by: 6)), id: \.self) { k in
                    Text(k == 0 ? "NOW" : label(hours[k].time))
                        .font(.mono(9)).foregroundStyle(state.skin.muted)
                        .fixedSize()
                        .position(x: g.size.width * CGFloat(k) / CGFloat(n), y: 24)
                        .onTapGesture { if k == 0 { withAnimation { selection = nil } } }
                }
                Circle().fill(state.skin.ink)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .position(x: x, y: 3)
            }
            .frame(height: 30, alignment: .top)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let k = Int((min(max(v.location.x, 0), g.size.width) / g.size.width * CGFloat(n)).rounded())
                    if k != (selection ?? 0) {
                        selection = k == 0 ? nil : k
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                })
        }
        .frame(height: 34)
    }

    private func label(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = state.forecast?.timeZone; f.dateFormat = "ha"
        return f.string(from: d).lowercased()
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
