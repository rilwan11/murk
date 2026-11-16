import SwiftUI
import Charts

struct RainView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Environment(\.pageActive) private var active
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var hero = RainHero()
    /// A day picked in the week card (nil = the live answer).
    @State private var day: Int?

    private var p: Palette { Palette(skin: state.skin, sky: sky) }

    var body: some View {
        let f = state.forecast
        let verdict: Verdict? = f.map { forecast in
            if let d = day, forecast.daily.indices.contains(d) { return dayVerdict(forecast, d) }
            return Verdicts.rain(forecast, now: Date(), unit: state.unit)
        }
        PageScaffold(title: String(localized: "Rain"), page: 2, verdict: verdict) {
            Hero3DView(hero: hero, active: active, label: heroLabel)
                .resettable { hero.resetCamera?(); day = nil }
                .overlay(alignment: .bottomLeading) { legend }
                .onAppear { hero.calm = reduceMotion; updateHero() }
                .onChange(of: heroKey) { _, _ in updateHero() }
                .onChange(of: reduceMotion) { _, v in hero.calm = v; updateHero() }
        } extra: {
            if let f, day == nil { NextThreeHours(forecast: f) }
        } cards: {
            if let f {
                GlassCard {
                    CardTitle(text: String(localized: "Next 24 hours"), trailing: String(localized: "bars: amount · line: chance"))
                    Next24Chart(forecast: f)
                }
                GlassCard { RadarCard(place: f.place) }
                GlassCard {
                    CardTitle(text: String(localized: "This week"), trailing: day == nil ? nil : String(localized: "tap again for now"))
                    WeekRain(forecast: f, selected: $day)
                }
                GlassCard {
                    CardTitle(text: String(localized: "Commute check"), trailing: String(localized: "change in Settings"))
                    ForEach(Array(Verdicts.commute(f, windows: state.commute.windows).enumerated()), id: \.offset) { _, row in
                        DetailRow(label: row.0, value: row.1, highlighted: row.1 != String(localized: "Dry"))
                    }
                }
            }
        } details: {
            if let f { details(f) }
        }
    }

    private var heroKey: String {
        "\(state.forecast?.fetchedAt.timeIntervalSince1970 ?? 0)-\(state.selectedHour ?? -1)-\(day ?? -1)-\(state.unit)"
    }

    /// The gauge holds what's expected for today (or the picked day); the cloud rains at the selected hour's intensity.
    private func updateHero() {
        guard let f = state.forecast else { return }
        let d = day.flatMap { f.daily.indices.contains($0) ? f.daily[$0] : nil } ?? f.daily.first
        let total = d?.precipSum ?? 0
        let h = state.selectedHourPoint
        let snow = (h?.snowfall ?? 0) > 0 || (h?.condition.precip ?? f.current.condition.precip) == .snow || d?.condition.precip == .snow
        let rate: Double = {
            if let h { return h.precip > 0 ? min(1, h.precip / 4 + 0.2) : (h.precipChance >= 50 ? 0.3 : 0) }
            if day != nil { return (d?.precipChance ?? 0) >= 50 ? 0.4 : 0 }
            return f.current.condition.precip != .none ? max(0.25, f.current.condition.intensity) : 0
        }()
        hero.configure(totalMM: total, metric: state.unit == .celsius, intensity: rate, snow: snow)
    }

    /// Says what the two parts of the scene mean.
    private var legend: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let dayName: String = {
            guard let f = state.forecast, let i = day, f.daily.indices.contains(i) else { return String(localized: "today") }
            return state.dayLabel(f.daily[i], index: i).lowercased()
        }()
        let when: String = state.selectedHourPoint.map { state.time($0.time) } ?? String(localized: "now")
        return VStack(alignment: .leading, spacing: 3) {
            Label { Text("GLASS · TOTAL \(dayName.uppercased())") } icon: { Image(systemName: "cylinder.fill") }
            Label { Text("CLOUD · RAIN \(when.uppercased())") } icon: { Image(systemName: "cloud.fill") }
        }
        .font(.mono(9)).tracking(1)
        .foregroundStyle(p.muted)
        .padding(.leading, 18).padding(.bottom, 6)
        .accessibilityHidden(true)
    }

    private var heroLabel: String {
        guard let f = state.forecast else { return String(localized: "Rain gauge") }
        let total = (day.flatMap { f.daily.indices.contains($0) ? f.daily[$0] : nil } ?? f.daily.first)?.precipSum ?? 0
        return String(localized: "Rain gauge holding \(state.unit.precip(total).lowercased()) expected today")
    }

    private func dayVerdict(_ f: Forecast, _ i: Int) -> Verdict {
        let d = f.daily[i]
        let name = state.dayLabel(d, index: i).capitalized
        let word = d.condition.precip == .snow ? String(localized: "snow") : String(localized: "rain")
        if d.precipChance < 30 { return Verdict(big: String(localized: "Dry"), line: String(localized: "\(name): \(d.precipChance)% chance of \(word)")) }
        return Verdict(big: "\(d.precipChance)%", unit: name,
                       line: String(localized: "\(name): about \(state.unit.precip(d.precipSum).lowercased()) of \(word)"))
    }

    private func todayStats(_ f: Forecast) -> (wetHours: Int, snow: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = f.timeZone
        let today = f.hourly.filter { cal.isDate($0.time, inSameDayAs: Date()) }
        return (today.filter { $0.precip >= 0.1 }.count, today.compactMap(\.snowfall).reduce(0, +))
    }

    @ViewBuilder private func details(_ f: Forecast) -> some View {
        let stats = todayStats(f)
        let wetHours = stats.wetHours
        let snow = stats.snow
        DetailRow(label: String(localized: "Today's total"), value: f.daily.first.map { state.unit.precip($0.precipSum) } ?? "--")
        DetailRow(label: String(localized: "Chance today"), value: f.daily.first.map { "\($0.precipChance)%" } ?? "--")
        DetailRow(label: String(localized: "Hours of rain"), value: "\(wetHours)")
        DetailRow(label: String(localized: "Snowfall today"), value: snow > 0 ? String(format: state.unit == .fahrenheit ? "%.1f IN" : "%.1f CM", state.unit == .fahrenheit ? snow / 2.54 : snow) : "--")
        DetailRow(label: String(localized: "Week total"), value: state.unit.precip(f.daily.reduce(0) { $0 + $1.precipSum }))
    }
}

/// 15-minute bars for the next 3 hours, shown only when rain is due within them.
private struct NextThreeHours: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    var body: some View {
        let now = Date()
        let pts = forecast.minutely.filter { $0.time.addingTimeInterval(900) > now }.prefix(12)
        if pts.contains(where: { $0.precip >= 0.1 }) {
            let p = Palette(skin: state.skin, sky: sky)
            let top = max(1.0, pts.map(\.precip).max() ?? 1)
            VStack(spacing: 4) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, m in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(m.precip >= 0.1 ? Color(hex: 0x3EA0FF) : p.line)
                            .frame(height: max(3, CGFloat(m.precip / top) * 40))
                    }
                }
                .frame(height: 40, alignment: .bottom)
                HStack {
                    Text("NOW"); Spacer(); Text("+1H"); Spacer(); Text("+2H"); Spacer(); Text("+3H")
                }
                .font(.mono(9)).foregroundStyle(p.muted)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Rain in the next three hours, in 15-minute steps"))
        }
    }
}

private struct Next24Chart: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let hours = Array(forecast.hourly.filter { $0.time.addingTimeInterval(3600) > Date() }.prefix(24))
        let maxMM = max(2.0, hours.map(\.precip).max() ?? 0)
        Chart {
            ForEach(hours) { h in
                BarMark(x: .value("Hour", h.time, unit: .hour), y: .value("Amount", h.precip / maxMM * 100))
                    .foregroundStyle(Color(hex: 0x3EA0FF).opacity(0.85))
                    .cornerRadius(2)
                LineMark(x: .value("Hour", h.time, unit: .hour), y: .value("Chance", h.precipChance))
                    .foregroundStyle(p.ink)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            if let sel = state.selectedHourPoint {
                RuleMark(x: .value("Selected", sel.time, unit: .hour))
                    .foregroundStyle(p.ink.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) { v in
            AxisGridLine().foregroundStyle(p.line)
            AxisValueLabel { if let n = v.as(Int.self) { Text("\(n)%") } }.font(.mono(9)).foregroundStyle(p.muted)
        } }
        .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
            AxisValueLabel(format: .dateTime.hour()).font(.mono(9)).foregroundStyle(p.muted)
        } }
        .frame(height: 130)
        .padding(.horizontal, 12)
        .accessibilityLabel(Text("Rain amount and chance for the next 24 hours"))
    }
}

private struct WeekRain: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    @Binding var selected: Int?
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(forecast.daily.enumerated()), id: \.offset) { i, d in
                let snow = d.condition.precip == .snow
                let on = selected == i
                VStack(spacing: 4) {
                    Text("\(d.precipChance)%").font(.mono(9)).foregroundStyle(p.muted)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(p.line).frame(width: 12, height: 64)
                        Capsule().fill(snow ? Color.white : Color(hex: 0x3EA0FF))
                            .frame(width: 12, height: max(6, CGFloat(d.precipChance) / 100 * 64))
                    }
                    Text(d.precipSum >= 0.1 ? state.unit.precip(d.precipSum).replacingOccurrences(of: " ", with: "\n") : "–")
                        .font(.mono(8)).multilineTextAlignment(.center).foregroundStyle(p.muted).frame(height: 22)
                    Text(state.dayLabel(d, index: i)).font(.mono(9, on ? .bold : .regular)).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(p.ink.opacity(on ? 0.14 : 0)))
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = on ? nil : i }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(state.dayLabel(d, index: i)), \(d.precipChance) percent, \(state.unit.precip(d.precipSum))"))
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 8)
    }
}
