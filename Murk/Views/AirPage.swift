import SwiftUI
import Charts

struct AirView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hero = AirHero()

    var body: some View {
        let f = state.forecast
        let h = state.selectedHourPoint
        PageScaffold(title: String(localized: "Air"), page: 1,
                     verdict: f.map { Verdicts.wind($0, at: h, now: state.selectedMoment, unit: state.unit) }) {
            Hero3DView(hero: hero, active: active, label: heroLabel)
                .onAppear { hero.calm = reduceMotion; updateHero() }
                .onChange(of: heroKey) { _, _ in updateHero() }
                .onChange(of: reduceMotion) { _, v in hero.calm = v; updateHero() }
        } extra: {
            if let f, let aqi = f.air?.aqi ?? f.aqi { AirChip(aqi: aqi) }
        } cards: {
            if let f {
                GlassCard {
                    CardTitle(text: String(localized: "Wind today"), trailing: state.unit == .fahrenheit ? "MPH" : "KM/H")
                    WindChart(forecast: f)
                }
                GlassCard {
                    CardTitle(text: String(localized: "Air quality"), trailing: "US AQI")
                    AirQualityCard(forecast: f)
                }
                GlassCard {
                    CardTitle(text: String(localized: "Comfort"))
                    ComfortTiles(forecast: f)
                }
            }
        } details: {
            if let f { details(f) }
        }
    }

    private var heroKey: String {
        let f = state.forecast
        return "\(f?.fetchedAt.timeIntervalSince1970 ?? 0)-\(state.selectedHour ?? -1)-\(f?.air?.aqi ?? f?.aqi ?? -1)"
    }

    private func updateHero() {
        guard let f = state.forecast else { return }
        let h = state.selectedHourPoint
        hero.configure(speedKmh: h?.windSpeed ?? f.current.windSpeed ?? 0,
                       from: h?.windDirection ?? f.current.windDirection ?? 0,
                       aqi: f.air?.aqi ?? f.aqi)
    }

    private var heroLabel: String {
        guard let f = state.forecast else { return String(localized: "Windsock") }
        let h = state.selectedHourPoint
        let speed = state.unit.wind(h?.windSpeed ?? f.current.windSpeed ?? 0).lowercased()
        let dir = (h?.windDirection ?? f.current.windDirection ?? 0).compassDirection
        return String(localized: "Windsock blowing in a \(speed) wind from the \(dir)")
    }

    @ViewBuilder private func details(_ f: Forecast) -> some View {
        let u = state.unit
        DetailRow(label: String(localized: "Wind direction"), value: f.current.windDirection.map { "\(Int($0.rounded()))° \($0.compassDirection)" } ?? "--")
        DetailRow(label: String(localized: "Gust now"), value: f.current.windGust.map(u.wind) ?? "--")
        DetailRow(label: String(localized: "Max gust today"), value: f.daily.first?.gustMax.map(u.wind) ?? "--")
        DetailRow(label: String(localized: "Pressure"), value: f.current.pressure.map(u.pressure) ?? "--")
        DetailRow(label: String(localized: "Visibility"), value: f.current.visibility.map(u.visibility) ?? "--")
        DetailRow(label: String(localized: "Humidity"), value: f.current.humidity.map { "\(Int($0.rounded()))%" } ?? "--")
        if let a = f.air {
            DetailRow(label: "PM2.5", value: a.pm25.map { String(format: "%.0f µG/M³", $0) } ?? "--")
            DetailRow(label: "PM10", value: a.pm10.map { String(format: "%.0f µG/M³", $0) } ?? "--")
            DetailRow(label: String(localized: "Ozone"), value: a.ozone.map { String(format: "%.0f µG/M³", $0) } ?? "--")
            DetailRow(label: "NO\u{2082}", value: a.no2.map { String(format: "%.0f µG/M³", $0) } ?? "--")
        }
    }
}

/// "Air good · AQI 42", colored by category and marked with a shape too, not color alone.
private struct AirChip: View {
    let aqi: Int
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: aqi <= 50 ? "leaf.fill" : (aqi <= 100 ? "circle.lefthalf.filled" : "exclamationmark.triangle.fill"))
                .font(.system(size: 11, weight: .bold))
            Text(String(localized: "Air \(Verdicts.aqiWord(aqi).lowercased()) · AQI \(aqi)")).font(.mono(11, .semibold)).tracking(0.5)
        }
        .foregroundStyle(Color(hex: 0x10161E))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color(hex: Verdicts.aqiHex(aqi))))
        .accessibilityElement(children: .combine)
    }
}

private struct WindChart: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let u = state.unit
        let hours = Array(forecast.hourly.filter { $0.time.addingTimeInterval(3600) > Date() }.prefix(24))
        let arrows = hours.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)
        let top = (hours.map { u.windValue($0.windGust ?? $0.windSpeed) }.max() ?? 10) * 1.1 + 2
        VStack(spacing: 10) {
            chart(hours: hours, top: top, p: p)
            WindDirections(hours: arrows, palette: p, timeZone: forecast.timeZone)
        }
    }

    private func chart(hours: [HourlyPoint], top: Double, p: Palette) -> some View {
        let u = state.unit
        return Chart {
            ForEach(hours) { h in
                AreaMark(x: .value("Hour", h.time, unit: .hour),
                         yStart: .value("Speed", u.windValue(h.windSpeed)),
                         yEnd: .value("Gust", u.windValue(max(h.windGust ?? h.windSpeed, h.windSpeed))))
                    .foregroundStyle(p.ink.opacity(0.18)).interpolationMethod(.catmullRom)
                LineMark(x: .value("Hour", h.time, unit: .hour), y: .value("Speed", u.windValue(h.windSpeed)))
                    .foregroundStyle(p.ink).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            if let sel = state.selectedHourPoint {
                RuleMark(x: .value("Selected", sel.time, unit: .hour)).foregroundStyle(p.ink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis { AxisMarks(position: .trailing) { _ in
            AxisGridLine().foregroundStyle(p.line)
            AxisValueLabel().font(.mono(9)).foregroundStyle(p.muted)
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
            AxisValueLabel(format: .dateTime.hour()).font(.mono(9)).foregroundStyle(p.muted)
        } }
        .frame(height: 140)
        .padding(.horizontal, 12)
        .accessibilityLabel(Text("Wind speed and gusts for the next 24 hours"))
    }
}

/// Every third hour: an arrow pointing where the wind is going, and the direction it comes from.
private struct WindDirections: View {
    let hours: [HourlyPoint]
    let palette: Palette
    let timeZone: TimeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ForEach(hours) { h in column(h) }
            }
            Text("Arrows point where the wind blows. Letters say where it comes from.")
                .font(.mono(9)).foregroundStyle(palette.muted)
                .padding(.horizontal, 12)
        }
    }

    private func column(_ h: HourlyPoint) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.up")
                .font(.system(size: 15, weight: .heavy))
                .rotationEffect(.degrees(h.windDirection + 180))
                .foregroundStyle(palette.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(palette.ink.opacity(0.1)))
            Text(h.windDirection.compassDirection).font(.mono(10, .bold)).foregroundStyle(palette.ink)
            Text(hourText(h.time)).font(.mono(9)).foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(hourText(h.time)), wind from \(h.windDirection.compassDirection)"))
    }

    private func hourText(_ d: Date) -> String {
        var f = Date.FormatStyle.dateTime.hour()
        f.timeZone = timeZone
        return d.formatted(f)
    }
}

private struct AirQualityCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let air = forecast.air
        if let aqi = air?.aqi ?? forecast.aqi {
            VStack(spacing: 10) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle().stroke(p.line, lineWidth: 10)
                        Circle().trim(from: 0, to: CGFloat(min(1, Double(aqi) / 300)))
                            .stroke(Color(hex: Verdicts.aqiHex(aqi)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(aqi)").font(.system(size: 28, weight: .black).width(.compressed))
                    }
                    .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Verdicts.aqiWord(aqi)).font(.system(size: 18, weight: .heavy))
                        if let main = air?.mainPollutant { Text(String(localized: "Mostly \(main)")).font(.mono(11)).foregroundStyle(p.muted) }
                        if let pollen = air?.pollen, !pollen.isEmpty {
                            Text(pollen.sorted { $0.key < $1.key }.map { "\($0.key) \(Int($0.value.rounded()))" }.joined(separator: " · "))
                                .font(.mono(10)).foregroundStyle(p.muted)
                        }
                    }
                    Spacer()
                }
                if let hourly = air?.hourly.filter({ $0.time.addingTimeInterval(3600) > Date() }).prefix(24), hourly.count > 2 {
                    Chart {
                        ForEach(Array(hourly), id: \.time) { h in
                            LineMark(x: .value("Hour", h.time, unit: .hour), y: .value("AQI", h.aqi))
                                .foregroundStyle(Color(hex: Verdicts.aqiHex(h.aqi))).interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100, 150]) { _ in
                        AxisGridLine().foregroundStyle(p.line)
                        AxisValueLabel().font(.mono(9)).foregroundStyle(p.muted)
                    } }
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisValueLabel(format: .dateTime.hour()).font(.mono(9)).foregroundStyle(p.muted)
                    } }
                    .frame(height: 80)
                    .accessibilityLabel(Text("Air quality for the next 24 hours"))
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 4)
            .accessibilityElement(children: .combine)
        } else {
            Text("Air quality isn't available here right now.").font(.footnote).foregroundStyle(p.muted)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14)
        }
    }
}

private struct ComfortTiles: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let now = state.selectedHourPoint ?? forecast.hourly.min { abs($0.time.timeIntervalSinceNow) < abs($1.time.timeIntervalSinceNow) }
        let humidity = now?.humidity ?? forecast.current.humidity
        let dew = now?.dewPoint
        let pressure = now?.pressure ?? forecast.current.pressure
        let trend = Verdicts.pressureTrend(forecast.hourly, now: state.selectedMoment)
        HStack(spacing: 8) {
            tile(String(localized: "Humidity"), humidity.map { "\(Int($0.rounded()))%" } ?? "--", nil, p)
            tile(String(localized: "Dew point"), dew.map { "\(state.unit.temp($0))°" } ?? "--", dew.map(Verdicts.dewWord), p)
            tile(String(localized: "Pressure"), pressure.map { state.unit.pressure($0).components(separatedBy: " ").first ?? "" } ?? "--",
                 trend.map(trendWord), p)
        }
        .padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func trendWord(_ t: Verdicts.Trend) -> String {
        switch t {
        case .rising: return String(localized: "↑ Rising")
        case .steady: return String(localized: "→ Steady")
        case .falling: return String(localized: "↓ Falling")
        }
    }

    private func tile(_ title: String, _ value: String, _ note: String?, _ p: Palette) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.mono(9)).tracking(1).foregroundStyle(p.muted)
            Text(value).font(.system(size: 24, weight: .black).width(.compressed)).lineLimit(1).minimumScaleFactor(0.6)
            Text(note ?? " ").font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(p.ink.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}
