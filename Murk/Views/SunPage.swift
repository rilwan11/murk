import SwiftUI
import Charts

struct SunView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Environment(\.pageActive) private var active
    @StateObject private var hero = SunHero()
    @State private var year: [DaylightDay] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            content(now: tl.date)
        }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let f = state.forecast
        PageScaffold(title: String(localized: "Sun"), page: 3, verdict: f.map { Verdicts.sun($0, now: now) }) {
            Hero3DView(hero: hero, active: active, label: heroLabel(now))
                .resettable { hero.resetCamera?() }
                .onChange(of: state.selectedHour) { _, _ in updateHero(now) }
                .onChange(of: state.forecast?.place.id) { _, _ in updateHero(now); year = [] }
                // Once a minute, keyed by the minute: an onChange on the timeline's date can fire twice in one frame.
                .task(id: Int(now.timeIntervalSince1970 / 60)) { updateHero(now) }
        } extra: {
            EmptyView()
        } cards: {
            if let f {
                let day = Verdicts.sunDay(latitude: f.place.latitude, longitude: f.place.longitude, day: now, timeZone: f.timeZone)
                GlassCard {
                    CardTitle(text: String(localized: "Today's light"))
                    LightBar(forecast: f, now: now, day: day)
                }
                GlassCard {
                    CardTitle(text: String(localized: "UV"), trailing: f.daily.first?.uvMax.map { String(localized: "max \(Int($0.rounded()))") })
                    UVChart(forecast: f, now: now)
                    Text(Verdicts.uvAdvice(f, now: now)).font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.bottom, 4)
                }
                GlassCard {
                    CardTitle(text: String(localized: "Daylight through the year"))
                    DaylightYear(days: year, now: now, timeZone: f.timeZone)
                }
                .task(id: f.place.id) { year = await DaylightDay.year(for: f, around: now) }
            }
        } details: {
            if let f { details(f, now: now) }
        }
    }

    private func updateHero(_ now: Date) {
        guard let f = state.forecast else { return }
        let t = state.selectedHourPoint?.time ?? now
        let lat = f.place.latitude, lon = f.place.longitude
        let s = Astronomy.sunPosition(latitude: lat, longitude: lon, at: t)
        let later = Astronomy.sunPosition(latitude: lat, longitude: lon, at: t.addingTimeInterval(1800)).altitude
        let m = Astronomy.moonPosition(latitude: lat, longitude: lon, at: t)
        hero.configure(sun: (s.altitude, s.azimuth), rising: later >= s.altitude, moon: (m.altitude, m.azimuth))
    }

    private func heroLabel(_ now: Date) -> String {
        guard let f = state.forecast else { return String(localized: "Island under the sun") }
        let s = Astronomy.sunPosition(latitude: f.place.latitude, longitude: f.place.longitude, at: state.selectedHourPoint?.time ?? now)
        if s.altitude < -1 { return String(localized: "Island at night, the sun below the horizon") }
        return String(localized: "Island with the sun \(Int(s.altitude.rounded())) degrees up in the \(s.azimuth.compassDirection), casting a shadow")
    }

    @ViewBuilder private func details(_ f: Forecast, now: Date) -> some View {
        let d = Verdicts.sunDay(latitude: f.place.latitude, longitude: f.place.longitude, day: now, timeZone: f.timeZone)
        let alt = Astronomy.sunPosition(latitude: f.place.latitude, longitude: f.place.longitude, at: now).altitude
        DetailRow(label: String(localized: "Sunrise"), value: state.time(d.sunrise))
        DetailRow(label: String(localized: "Sunset"), value: state.time(d.sunset))
        DetailRow(label: String(localized: "Solar noon"), value: state.time(d.noon))
        DetailRow(label: String(localized: "Sun height now"), value: "\(Int(alt.rounded()))°")
        DetailRow(label: String(localized: "Golden hour"), value: state.time(d.goldenEveningStart))
        DetailRow(label: String(localized: "Civil dawn · dusk"), value: "\(state.time(d.civilDawn)) · \(state.time(d.civilDusk))")
        DetailRow(label: String(localized: "Nautical"), value: "\(state.time(d.nauticalDawn)) · \(state.time(d.nauticalDusk))")
        DetailRow(label: String(localized: "Astronomical"), value: "\(state.time(d.astroDawn)) · \(state.time(d.astroDusk))")
        ForEach(Array(f.daily.prefix(7).enumerated()), id: \.offset) { i, day in
            DetailRow(label: String(localized: "Sunset \(state.dayLabel(day, index: i))"), value: state.time(day.sunset))
        }
    }
}

/// Midnight to midnight in one bar: night, twilight, blue hour, golden hour and day, with now marked.
private struct LightBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    let now: Date
    let day: Verdicts.SunDay

    static func color(_ alt: Double) -> Color {
        switch alt {
        case 6...: return Color(hex: 0xFFE7A3)
        case -4..<6: return Color(hex: 0xFF9A3C)
        case -6 ..< -4: return Color(hex: 0x3B6FD8)
        case -12 ..< -6: return Color(hex: 0x223A78)
        default: return Color(hex: 0x0B1430)
        }
    }

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let cal = Calendar.zoned(forecast.timeZone)
        let start = cal.startOfDay(for: now)
        let lat = forecast.place.latitude, lon = forecast.place.longitude
        let steps = 144
        let alts: [Double] = (0..<steps).map { i in
            Astronomy.sunPosition(latitude: lat, longitude: lon, at: start.addingTimeInterval(Double(i) * 600 + 300)).altitude
        }
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                let x: (Date) -> CGFloat = { d in CGFloat(min(1, max(0, d.timeIntervalSince(start) / 86400))) * w }
                ZStack(alignment: .leading) {
                    Canvas { ctx, size in
                        let bw = size.width / CGFloat(steps)
                        for (i, a) in alts.enumerated() {
                            ctx.fill(Path(CGRect(x: CGFloat(i) * bw, y: 0, width: bw + 0.5, height: size.height)), with: .color(Self.color(a)))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Rectangle().fill(Color.white).frame(width: 2, height: 34).offset(x: x(now) - 1)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                }
            }
            .frame(height: 28)
            GeometryReader { g in
                let w = g.size.width
                let x: (Date) -> CGFloat = { d in CGFloat(min(1, max(0, d.timeIntervalSince(start) / 86400))) * w }
                ZStack(alignment: .topLeading) {
                    if let r = day.sunrise { mark("sunrise.fill", state.time(r)).position(x: min(max(x(r), 30), w - 30), y: 14) }
                    if let s = day.sunset { mark("sunset.fill", state.time(s)).position(x: min(max(x(s), 30), w - 30), y: 14) }
                }
            }
            .frame(height: 28)
            HStack(spacing: 10) {
                legend(Self.color(20), String(localized: "Day"))
                legend(Self.color(0), String(localized: "Golden"))
                legend(Self.color(-5), String(localized: "Blue hour"))
                legend(Self.color(-20), String(localized: "Night"))
            }
            .font(.mono(9)).foregroundStyle(p.muted)
        }
        .padding(.horizontal, 14).padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Sunrise \(state.time(day.sunrise)), golden hour from \(state.time(day.goldenEveningStart)), sunset \(state.time(day.sunset))"))
    }

    private func mark(_ icon: String, _ time: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).symbolRenderingMode(.multicolor).font(.system(size: 11))
            Text(time).font(.mono(10))
        }
        .fixedSize()
    }

    private func legend(_ c: Color, _ name: String) -> some View {
        HStack(spacing: 4) { Circle().fill(c).frame(width: 8, height: 8); Text(name) }
    }
}

private struct UVChart: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    let now: Date
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let cal = Calendar.zoned(forecast.timeZone)
        let hours = forecast.hourly.filter { cal.isDate($0.time, inSameDayAs: now) && ($0.uvIndex != nil) }
        let bands = Gradient(stops: [
            .init(color: Color(hex: 0x3CC864), location: 0), .init(color: Color(hex: 0xF2C230), location: 0.3),
            .init(color: Color(hex: 0xF08A2C), location: 0.55), .init(color: Color(hex: 0xE5484D), location: 0.75),
            .init(color: Color(hex: 0x9C4DCC), location: 1),
        ])
        Chart {
            ForEach(hours) { h in
                AreaMark(x: .value("Hour", h.time, unit: .hour), y: .value("UV", h.uvIndex ?? 0))
                    .foregroundStyle(LinearGradient(gradient: bands, startPoint: .bottom, endPoint: .top).opacity(0.75))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Hour", h.time, unit: .hour), y: .value("UV", h.uvIndex ?? 0))
                    .foregroundStyle(p.ink).interpolationMethod(.catmullRom)
            }
            RuleMark(x: .value("Now", now)).foregroundStyle(p.ink.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        .chartYScale(domain: 0...12)
        .chartYAxis { AxisMarks(position: .trailing, values: [0, 3, 6, 8, 11]) { v in
            AxisGridLine().foregroundStyle(p.line)
            AxisValueLabel().font(.mono(9)).foregroundStyle(p.muted)
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
            AxisValueLabel(format: .dateTime.hour()).font(.mono(9)).foregroundStyle(p.muted)
        } }
        .frame(height: 120)
        .padding(.horizontal, 12)
        .accessibilityLabel(Text("UV index by hour today"))
    }
}

struct DaylightDay: Identifiable, Equatable {
    var id: Date { date }
    var date: Date
    var hours: Double

    /// Day length for every day from 182 days ago to 182 days ahead, computed off the main thread.
    static func year(for f: Forecast, around now: Date) async -> [DaylightDay] {
        let lat = f.place.latitude, lon = f.place.longitude, tz = f.timeZone
        return await Task.detached(priority: .utility) {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
            let today = cal.startOfDay(for: now)
            return (-182...182).compactMap { k -> DaylightDay? in
                guard let d = cal.date(byAdding: .day, value: k, to: today) else { return nil }
                return DaylightDay(date: d, hours: Astronomy.dayLength(latitude: lat, longitude: lon, day: d, calendar: cal))
            }
        }.value
    }
}

private struct DaylightYear: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let days: [DaylightDay]
    let now: Date
    let timeZone: TimeZone

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let mid = days.count / 2
        if days.count > 2 {
            let today = days[mid], yesterday = days[mid - 1]
            let delta = (today.hours - yesterday.hours) * 3600
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    ForEach(days) { d in
                        LineMark(x: .value("Date", d.date), y: .value("Hours", d.hours))
                            .foregroundStyle(Color(hex: 0xFFC14D)).lineStyle(StrokeStyle(lineWidth: 2.5))
                    }
                    PointMark(x: .value("Date", today.date), y: .value("Hours", today.hours))
                        .foregroundStyle(p.ink).symbolSize(70)
                }
                .chartYAxis { AxisMarks(position: .trailing) { v in
                    AxisGridLine().foregroundStyle(p.line)
                    AxisValueLabel { if let h = v.as(Double.self) { Text("\(Int(h))h") } }.font(.mono(9)).foregroundStyle(p.muted)
                } }
                .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.mono(9)).foregroundStyle(p.muted)
                } }
                .frame(height: 120)
                Text(Self.deltaText(delta) + " · " + nextExtreme(from: mid))
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        } else {
            ProgressView().frame(height: 120).frame(maxWidth: .infinity)
        }
    }

    static func deltaText(_ seconds: Double) -> String {
        let s = Int(abs(seconds).rounded())
        let sign = seconds >= 0 ? "+" : "−"
        let body = s >= 60 ? String(localized: "\(s / 60) min \(s % 60) s") : String(localized: "\(s) s")
        return String(localized: "\(sign)\(body) vs yesterday")
    }

    private func nextExtreme(from i: Int) -> String {
        let ahead = days[i...]
        let growing = days[min(i + 1, days.count - 1)].hours >= days[i].hours
        guard let target = growing ? ahead.max(by: { $0.hours < $1.hours }) : ahead.min(by: { $0.hours < $1.hours }) else { return "" }
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.abbreviated).day()
        style.timeZone = timeZone
        return growing ? String(localized: "longest day \(target.date.formatted(style))") : String(localized: "shortest day \(target.date.formatted(style))")
    }
}

extension Calendar {
    /// A Gregorian calendar in a given time zone.
    static func zoned(_ tz: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz
        return c
    }
}
