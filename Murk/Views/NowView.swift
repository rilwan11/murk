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
    @State private var showAlerts = false
    @AppStorage("locationPromptDismissed") private var locationPromptDismissed = false
    @Environment(\.pageActive) private var pageActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The live sky for whatever moment the scene is showing (nil on the light skins, which keep their flat color).
    private func makeSky(for c: SceneConfig?) -> Sky? {
        guard let c, !state.skin.isLight else { return nil }
        return Sky.at(altitude: c.isDay ? c.sunAltitude : min(c.sunAltitude, -12),
                      cover: c.cover, precip: c.precip != .none)
    }
    private var ink: Color { makeSky(for: sceneConfig)?.ink ?? state.skin.ink }
    private var muted: Color { makeSky(for: sceneConfig)?.muted ?? state.skin.muted }
    private var line: Color { makeSky(for: sceneConfig)?.line ?? state.skin.line }

    var body: some View {
        let skin = state.skin
        let config = sceneConfig
        let sky = makeSky(for: config)
        VStack(spacing: 0) {
            header
            if !state.useLocation && !locationPromptDismissed && state.forecast != nil {
                HStack(spacing: 4) {
                    Button { locationPromptDismissed = true; state.selectCurrentLocation() } label: {
                        Label("USE MY LOCATION", systemImage: "location.fill").font(.mono(11)).tracking(1.5)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().stroke(line))
                    }
                    Button { locationPromptDismissed = true } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 30, height: 30)
                    }
                    .accessibilityLabel("Dismiss")
                }
                .foregroundStyle(ink)
                .padding(.top, 6)
            }
            if let pill = state.headsUp {
                let alert = state.topAlert
                let isAlert = alert != nil
                Button { if isAlert { showAlerts = true } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isAlert ? (alert?.isSevere == true ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill") : "cloud.rain.fill")
                            .font(.system(size: 12))
                        Text(pill).font(.mono(12)).tracking(2).lineLimit(1).minimumScaleFactor(0.7)
                        if isAlert { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, alert?.isSevere == true ? 10 : 7)
                    .foregroundStyle(isAlert ? Color.white : (sky == nil ? skin.bg : (sky!.bright ? Color.white : Color(hex: 0x13233D))))
                    .background(Capsule().fill(isAlert ? Color(hex: 0xC42F21) : ink))
                    // Severe alerts get a second outline, so they stand out by shape as well as color.
                    .overlay { if alert?.isSevere == true { Capsule().stroke(Color.white, lineWidth: 2).padding(3) } }
                }
                .buttonStyle(.plain)
                .disabled(!isAlert)
                .accessibilityLabel(isAlert ? Text("Weather alert: \(pill)") : Text(pill))
                .accessibilityHint(isAlert ? Text("Shows the alert details") : Text(""))
                .padding(.top, 8)
                .transition(.opacity)
            }

            ZStack(alignment: .bottom) {
                if let config {
                    WeatherSceneView(config: config, active: pageActive, calm: reduceMotion,
                                     onThunder: { SoundEngine.shared.thunder() })
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isImage)
                        .accessibilityLabel(Text(sceneDescription))
                        .accessibilityHint(Text("A 3D scene of the weather. Double tap for new clouds."))
                        .accessibilityIdentifier("scene")
                } else if state.isLoading || state.activePlace != nil && state.failure == nil {
                    ProgressView().tint(ink).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyState
                }
                HStack {
                    Spacer()
                    Text("DRAG TO SPIN · PINCH TO ZOOM · TAP FOR NEW CLOUDS")
                        .accessibilityHidden(true)
                        .font(.mono(9)).tracking(1).foregroundStyle(muted)
                        .opacity(showHint ? 1 : 0)
                    Spacer()
                }
                .overlay(alignment: .trailing) {
                    Button { reset += 1; UIImpactFeedbackGenerator(style: .light).impactOccurred() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().stroke(line))
                    }
                    .accessibilityLabel("Reset the view")
                    .foregroundStyle(ink)
                    .padding(.trailing, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .noPageSwipe(page: 0)
            .task { try? await Task.sleep(for: .seconds(6)); withAnimation { showHint = false } }

            Text(conditionTitle)
                .font(.display(36)).tracking(-1)
                .minimumScaleFactor(0.6).lineLimit(1)
                .padding(.top, 6).padding(.horizontal, 20)
            if let feels = feelsLike {
                Text("FEELS LIKE \(feels)°").font(.mono(10)).tracking(1.5).foregroundStyle(sky == nil ? muted : ink)
                    .padding(.horizontal, sky == nil ? 0 : 12).padding(.vertical, sky == nil ? 0 : 5)
                    .background { if let sky { Capsule().fill(sky.glass) } }
                    .padding(.top, 2)
            }
            if selectedDay == 0, hour == nil, !state.minimal, let f = state.forecast, let next = Outlook.summary(f, unit: state.unit) {
                Label(next, systemImage: "arrow.turn.down.right").font(.mono(10)).tracking(1.2)
                    .foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 4).padding(.horizontal, 20)
                    .accessibilityLabel(Text("Coming up: \(next.capitalized)"))
            }

            if !state.upcomingHours.isEmpty {
                HourScrubber(hours: state.upcomingHours, selection: $hour)
                    .padding(.top, 10).padding(.horizontal, 22)
                    .noPageSwipe(page: 0)
            }

            if !state.minimal {
                ForecastStrip(selected: $selectedDay)
                    .padding(.vertical, sky == nil ? 0 : 4)
                    .background { if let sky { RoundedRectangle(cornerRadius: 18).fill(sky.glass).padding(.horizontal, 8) } }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            footer
        }
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(ink)
        .environment(\.sky, sky)
        .background {
            if let sky { SkyBackground(sky: sky).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.8), value: sky)
        .animation(.easeInOut(duration: 0.3), value: state.minimal)
        .onChange(of: state.forecast?.place.id) { _, _ in selectedDay = 0; hour = nil }
        .onChange(of: selectedDay) { _, d in if d > 0 { hour = nil } }
        .onChange(of: hour) { _, h in if h != nil { selectedDay = 0 } }
        .onChange(of: soundKey) { _, _ in updateSound(config) }
        .onAppear { updateSound(config) }
        .sheet(isPresented: $showAlerts) {
            AlertSheet(alerts: state.forecast?.alerts ?? [], place: state.forecast?.place.name ?? "", time: { state.time($0) })
        }
    }

    /// Nothing to show yet: say why and offer the ways forward.
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: state.failure.map(AppState.symbol) ?? "cloud").font(.system(size: 40, weight: .semibold))
            Text(state.failure.map { AppState.describe($0) } ?? String(localized: "NO PLACE CHOSEN YET."))
                .font(.mono(12)).tracking(1.5).multilineTextAlignment(.center)
            if state.failure != nil {
                Button("Try again") { state.retry() }.buttonStyle(.bordered)
            }
            if state.activePlace == nil {
                Button("Use Current Location") { state.selectCurrentLocation() }.buttonStyle(.borderedProminent)
                Button("Choose a city") { showSettings = true }.buttonStyle(.bordered)
            }
        }
        .foregroundStyle(ink)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What the 3D scene shows, in words.
    private var sceneDescription: String {
        guard let f = state.forecast else { return "" }
        let t = hourPoint.map { state.unit.temp($0.temperature) } ?? state.unit.temp(f.current.temperature)
        var parts = [conditionTitle, String(localized: "\(t) degrees")]
        if let feels = feelsLike { parts.append(String(localized: "feels like \(feels)")) }
        return parts.joined(separator: ", ")
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
                .accessibilityLabel("Previous place")
                .accessibilityHidden(count < 2)
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
                .accessibilityHint("Opens places and settings")
                .accessibilityIdentifier("placeName")
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 22, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier("settingsButton")
            }
            .foregroundStyle(ink)
            if count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle().fill(ink.opacity(i == state.cityIndex ? 0.9 : 0.25)).frame(width: 5, height: 5)
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
        .noPageSwipe(page: 0)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            Group {
                if state.forecast != nil, let h = hourPoint {
                    Text("\(hourLabel(h.time)) · \(h.precipChance)% RAIN · TAP NOW TO RETURN")
                } else if let f = state.forecast, selectedDay > 0, selectedDay < f.daily.count {
                    let day = f.daily[selectedDay]
                    Text("\(state.dayLabel(day, index: selectedDay)) HIGH · \(day.precipChance)% RAIN · TAP TODAY TO RETURN")
                } else if let st = state.status(now: tl.date) {
                    // How fresh the forecast is, and a quiet way to retry when it isn't.
                    Button { if st.canRetry { state.retry() } } label: {
                        Label(st.text, systemImage: st.symbol)
                            .foregroundStyle(st.isProblem ? ink : muted)
                    }
                    .buttonStyle(.plain)
                    .disabled(!st.canRetry)
                    .accessibilityHint(st.canRetry ? Text("Refreshes the forecast") : Text(""))
                    .accessibilityIdentifier("status")
                }
            }
            .font(.mono(9)).tracking(1.2)
            .foregroundStyle(muted)
            .multilineTextAlignment(.center)
            .padding(.top, 12).padding(.horizontal, 20)
        }
    }

    // MARK: Derived

    private var hourPoint: HourlyPoint? {
        guard let i = hour, state.upcomingHours.indices.contains(i), i > 0 else { return nil }
        return state.upcomingHours[i]
    }

    private func hourLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = state.forecast?.timeZone; f.setLocalizedDateFormatFromTemplate("j")
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
        var moment = Date()
        var precip: Precip, intensity: Double
        if let h = hourPoint {
            cond = h.condition; temp = h.temperature; isDay = h.isDay
            wind = h.windSpeed; dir = h.windDirection
            alt = Astronomy.sunAltitude(latitude: lat, longitude: lon, at: h.time)
            moment = h.time
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
            sunRising: Astronomy.sunAltitude(latitude: lat, longitude: lon, at: moment.addingTimeInterval(1800)) >= alt,
            moonAltitude: (Self.moonAltitude(lat, lon, moment) / 2).rounded() * 2,
            moonRising: Self.moonAltitude(lat, lon, moment.addingTimeInterval(1800)) >= Self.moonAltitude(lat, lon, moment),
            regenToken: regen,
            resetToken: reset)
    }

    /// The moon follows roughly the sun's path, running behind it by its age
    /// (a full moon rides highest at midnight, a new moon travels with the sun).
    static func moonAltitude(_ lat: Double, _ lon: Double, _ date: Date) -> Double {
        let lag = Astronomy.moonAge(date) / Astronomy.synodicMonth * 86_400
        return Astronomy.sunAltitude(latitude: lat, longitude: lon, at: date.addingTimeInterval(-lag))
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

/// Drag across the next 24 hours to play the weather forward. The track is painted with the
/// day's sky, carries a temperature curve with the high and low, marks sunrise and sunset,
/// and shows a bubble with the time, temperature and weather while you drag.
struct HourScrubber: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    private var ink: Color { sky?.ink ?? state.skin.ink }
    private var muted: Color { sky?.muted ?? state.skin.muted }
    private var line: Color { sky?.line ?? state.skin.line }
    let hours: [HourlyPoint]
    @Binding var selection: Int?
    @State private var dragging = false

    private let trackH: CGFloat = 30
    private let bubbleH: CGFloat = 30

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let n = max(1, hours.count - 1)
            let i = selection ?? 0
            let x = w * CGFloat(i) / CGFloat(n)
            let trackTop = bubbleH + 6
            ZStack(alignment: .topLeading) {
                // Track: the sky, hour by hour.
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(stops: skyStops(n: n), startPoint: .leading, endPoint: .trailing))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(line, lineWidth: 1))
                    .overlay { curve(width: w, n: n) }
                    .frame(width: w, height: trackH)
                    .offset(y: trackTop)

                // Sunrise / sunset markers.
                ForEach(sunEvents(), id: \.0) { k, rise in
                    Image(systemName: rise ? "sunrise.fill" : "sunset.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(hex: 0xFFC44D), muted)
                        .font(.system(size: 11, weight: .bold))
                        .position(x: w * CGFloat(k) / CGFloat(n), y: trackTop + trackH + 9)
                }

                // Hour labels.
                ForEach(Array(stride(from: 0, through: n, by: 6)), id: \.self) { k in
                    Text(k == 0 ? "NOW" : label(hours[k].time))
                        .font(.mono(9)).foregroundStyle(muted)
                        .fixedSize()
                        .position(x: min(max(w * CGFloat(k) / CGFloat(n), 14), w - 14), y: trackTop + trackH + 22)
                        .onTapGesture { if k == 0 { withAnimation { selection = nil } } }
                }

                // Thumb.
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 6, height: trackH + 10)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .position(x: min(max(x, 3), w - 3), y: trackTop + trackH / 2)

                // Bubble.
                if selection != nil || dragging, hours.indices.contains(i) {
                    bubble(hours[i], now: i == 0)
                        .fixedSize()
                        .position(x: min(max(x, 70), w - 70), y: bubbleH / 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { withAnimation(.easeOut(duration: 0.15)) { dragging = true } }
                    let k = Int((min(max(v.location.x, 0), w) / w * CGFloat(n)).rounded())
                    if k != (selection ?? 0) {
                        selection = k == 0 ? nil : k
                        if isSunEvent(k) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        else { UISelectionFeedbackGenerator().selectionChanged() }
                    }
                }
                .onEnded { _ in withAnimation(.easeOut(duration: 0.3)) { dragging = false } })
        }
        .frame(height: bubbleH + 6 + trackH + 30)
        .animation(.easeOut(duration: 0.15), value: selection == nil)
        .accessibilityElement()
        .accessibilityLabel(Text("Hour by hour"))
        .accessibilityValue(Text(spoken(selection ?? 0)))
        .accessibilityHint(Text("Swipe up or down to move through the next 24 hours"))
        .accessibilityAdjustableAction { direction in
            let i = selection ?? 0
            switch direction {
            case .increment: selection = min(i + 1, hours.count - 1)
            case .decrement: selection = i - 1 <= 0 ? nil : i - 1
            @unknown default: break
            }
        }
    }

    // MARK: Pieces

    private func bubble(_ h: HourlyPoint, now: Bool) -> some View {
        HStack(spacing: 6) {
            Text(now ? "NOW" : label(h.time).uppercased()).font(.mono(11)).tracking(0.5)
            Text("\(state.unit.temp(h.temperature))°").font(.system(size: 15, weight: .heavy))
            Image(systemName: h.condition.symbol).symbolRenderingMode(.multicolor).font(.system(size: 14, weight: .semibold))
            if h.precipChance >= 20 {
                Text("\(h.precipChance)%").font(.mono(10)).foregroundStyle(Color(hex: 0x6FB3FF))
            }
        }
        .foregroundStyle(sky?.bright == true ? Color(hex: 0x13233D) : .white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(sky?.bright == true ? Color.white.opacity(0.85) : Color.black.opacity(0.55)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
    }

    /// Temperature line across the track, with the high and low marked.
    private func curve(width w: CGFloat, n: Int) -> some View {
        let temps = hours.map(\.temperature)
        let lo = temps.min() ?? 0, hi = temps.max() ?? 1
        let span = max(hi - lo, 1)
        let pad: CGFloat = 7
        func pt(_ k: Int) -> CGPoint {
            CGPoint(x: w * CGFloat(k) / CGFloat(n),
                    y: pad + (trackH - pad * 2) * CGFloat(1 - (temps[k] - lo) / span))
        }
        let hiK = temps.firstIndex(of: hi) ?? 0, loK = temps.firstIndex(of: lo) ?? 0
        return ZStack {
            Path { p in
                guard temps.count > 1 else { return }
                p.move(to: pt(0))
                for k in 1..<temps.count {
                    let a = pt(k - 1), b = pt(k)
                    p.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                }
            }
            .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: .black.opacity(0.35), radius: 1.5)
            if temps.count > 1 {
                marker(state.unit.temp(hi), at: pt(hiK), above: true, w: w)
                marker(state.unit.temp(lo), at: pt(loK), above: false, w: w)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func marker(_ t: Int, at p: CGPoint, above: Bool, w: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.white).frame(width: 5, height: 5).position(p)
            Text("\(t)°").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .fixedSize()
                .position(x: min(max(p.x, 12), w - 12), y: above ? max(p.y - 0.5, 6) + 6 : min(p.y + 0.5, trackH - 6) - 6)
                .offset(x: p.x < w - 24 ? 12 : -12)
        }
    }

    // MARK: Data

    private var place: Place? { state.forecast?.place }

    private func skyStops(n: Int) -> [Gradient.Stop] {
        guard let place, hours.count > 1 else { return [.init(color: line, location: 0), .init(color: line, location: 1)] }
        return hours.enumerated().map { k, h in
            let alt = Astronomy.sunAltitude(latitude: place.latitude, longitude: place.longitude, at: h.time)
            let s = Sky.at(altitude: alt, cover: h.condition.cloudCover, precip: h.condition.precip != .none)
            return .init(color: Color(hex: Sky.lerp(s.mid, s.top, 0.35)), location: CGFloat(k) / CGFloat(n))
        }
    }

    /// (index, isSunrise) where day turns to night or back.
    private func sunEvents() -> [(Int, Bool)] {
        guard hours.count > 1 else { return [] }
        return (1..<hours.count).compactMap { k in
            hours[k].isDay != hours[k - 1].isDay ? (k, hours[k].isDay) : nil
        }
    }

    private func spoken(_ i: Int) -> String {
        guard hours.indices.contains(i) else { return "" }
        let h = hours[i]
        let when = i == 0 ? String(localized: "Now") : label(h.time)
        return String(localized: "\(when), \(state.unit.temp(h.temperature)) degrees, \(h.condition.title), \(h.precipChance) percent chance of rain")
    }

    private func isSunEvent(_ k: Int) -> Bool { sunEvents().contains { $0.0 == k } }

    private func label(_ d: Date) -> String {
        let f = DateFormatter(); f.timeZone = state.forecast?.timeZone; f.setLocalizedDateFormatFromTemplate("j")
        return f.string(from: d).lowercased().replacingOccurrences(of: " ", with: "")
    }
}

struct ForecastStrip: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    private var ink: Color { sky?.ink ?? state.skin.ink }
    private var muted: Color { sky?.muted ?? state.skin.muted }
    private var line: Color { sky?.line ?? state.skin.line }
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
                        .foregroundStyle(muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14).fill(ink.opacity(i == selected ? 0.12 : 0)))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = i }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(state.dayLabel(d, index: i).capitalized), \(d.condition.title), high \(state.unit.temp(d.high)), low \(state.unit.temp(d.low)), \(d.precipChance) percent chance of rain"))
                .accessibilityAddTraits(i == selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 12)
    }
}
