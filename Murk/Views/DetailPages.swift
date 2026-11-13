import SwiftUI
import Charts

// MARK: - Shared day picker

struct DayPicker: View {
    @EnvironmentObject var state: AppState
    @Binding var selected: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                Text(state.dayLabel(d, index: i))
                    .font(.mono(10)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(i == selected ? state.skin.ink : state.skin.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { selected = i } }
            }
        }
    }
}

struct DetailScroll<Art: View, Content: View>: View {
    @ViewBuilder var art: Art
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                art.frame(height: 300).padding(.top, 30).padding(.bottom, 10)
                VStack(spacing: 2) { content }.detailPage()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Air

struct AirView: View {
    @EnvironmentObject var state: AppState
    @State private var sel = 0

    var body: some View {
        let u = state.unit
        let f = state.forecast
        let d = f.flatMap { sel < $0.daily.count ? $0.daily[sel] : nil }
        let today = sel == 0
        DetailScroll {
            Anemometer(speedKmh: (today ? f?.current.windSpeed : d?.windMax) ?? 0,
                       direction: today ? f?.current.windDirection : nil)
        } content: {
            PageTitle(text: "Air")
            DetailRow(label: today ? "Wind speed" : "Max wind", value: ((today ? f?.current.windSpeed : d?.windMax)).map(u.wind) ?? "--", highlighted: true)
            DetailRow(label: today ? "Wind gust" : "Max gust", value: ((today ? f?.current.windGust : d?.gustMax)).map(u.wind) ?? "--")
            DetailRow(label: "Wind direction", value: today ? (f?.current.windDirection?.compassDirection ?? "--") : "--")
            DetailRow(label: "Humidity", value: today ? (f?.current.humidity.map { "\(Int($0.rounded()))%" } ?? "--") : "--")
            DetailRow(label: "Pressure", value: today ? (f?.current.pressure.map(u.pressure) ?? "--") : "--")
            DetailRow(label: "Visibility", value: today ? (f?.current.visibility.map(u.visibility) ?? "--") : "--")
            DetailRow(label: "AQI", value: today ? (f?.aqi.map { "\($0) \(aqiLabel($0))" } ?? "--") : "--")
            DetailRow(label: today ? "UV now" : "UV max", value: ((today ? f?.current.uvIndex : d?.uvMax)).map { String(Int($0.rounded())) } ?? "--")

            if let f, !f.daily.isEmpty {
                Chart {
                    ForEach(Array(f.daily.enumerated()), id: \.offset) { i, day in
                        if let g = day.gustMax {
                            LineMark(x: .value("Day", i), y: .value("Wind", u.windValue(g)), series: .value("S", "Gust"))
                                .foregroundStyle(state.skin.muted).interpolationMethod(.catmullRom)
                        }
                        if let w = day.windMax {
                            LineMark(x: .value("Day", i), y: .value("Wind", u.windValue(w)), series: .value("S", "Wind"))
                                .foregroundStyle(state.skin.ink).lineStyle(StrokeStyle(lineWidth: 3)).interpolationMethod(.catmullRom)
                        }
                    }
                    RuleMark(x: .value("Day", sel)).foregroundStyle(state.skin.line).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing) { _ in AxisValueLabel().font(.mono(10)).foregroundStyle(state.skin.muted) } }
                .frame(height: 140).padding(.top, 18).padding(.horizontal, 8)
                DayPicker(selected: $sel)
                Note(text: "White: max wind · grey: max gust (\(u.windLabel))")
            }
        }
    }
}

/// Spinning cup anemometer drawn in fake 3D; spins faster with more wind and points into the wind.
struct Anemometer: View {
    @EnvironmentObject var state: AppState
    let speedKmh: Double
    let direction: Double?

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let spin = CGFloat(t * max(0.4, speedKmh * 0.12))
                let cx = size.width / 2, top = size.height * 0.28, R = min(size.width * 0.32, 120.0), tilt: CGFloat = 0.34
                let skin = state.skin
                let dark = Color(hex: skin.cloudHex), lit = Color(hex: skin.cloudHex).opacity(0.65)

                // shadow, pole, compass ring
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 70, y: size.height - 22, width: 140, height: 16)), with: .color(.black.opacity(0.25)))
                ctx.fill(Path(roundedRect: CGRect(x: cx - 4, y: top, width: 8, height: size.height - top - 16), cornerRadius: 3), with: .color(dark))
                let ringY = size.height * 0.62
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - R * 1.25, y: ringY - R * 1.25 * tilt, width: R * 2.5, height: R * 2.5 * tilt)), with: .color(skin.line), lineWidth: 4)
                for (label, a) in [("N", -90.0), ("E", 0.0), ("S", 90.0), ("W", 180.0)] {
                    let r = CGFloat(a) * .pi / 180
                    ctx.draw(Text(label).font(.mono(11)).foregroundColor(skin.muted),
                             at: CGPoint(x: cx + cos(r) * R * 1.45, y: ringY + sin(r) * R * 1.45 * tilt))
                }
                if let dir = direction {
                    // arrow pointing where the wind blows toward
                    let r = CGFloat(dir + 90) * .pi / 180
                    let tip = CGPoint(x: cx + cos(r) * R * 1.1, y: ringY + sin(r) * R * 1.1 * tilt)
                    var p = Path(); p.move(to: CGPoint(x: cx - cos(r) * R * 1.1, y: ringY - sin(r) * R * 1.1 * tilt)); p.addLine(to: tip)
                    ctx.stroke(p, with: .color(skin.sun), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)), with: .color(skin.sun))
                }

                // arms + cups, back to front
                let cups = (0..<3).map { k -> (CGPoint, CGFloat) in
                    let a = spin + CGFloat(k) * 2 * .pi / 3
                    return (CGPoint(x: cx + cos(a) * R, y: top + sin(a) * R * tilt), sin(a))
                }.sorted { $0.1 < $1.1 }
                for (pt, depth) in cups {
                    var arm = Path(); arm.move(to: CGPoint(x: cx, y: top)); arm.addLine(to: pt)
                    ctx.stroke(arm, with: .color(dark), lineWidth: 5)
                    let s = 26 * (0.85 + 0.15 * depth)
                    ctx.fill(Path(ellipseIn: CGRect(x: pt.x - s, y: pt.y - s * 0.8, width: 2 * s, height: 1.6 * s)),
                             with: .linearGradient(Gradient(colors: [lit, dark]), startPoint: CGPoint(x: pt.x - s, y: pt.y - s), endPoint: CGPoint(x: pt.x + s, y: pt.y + s)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 10, y: top - 10, width: 20, height: 20)), with: .color(dark))
            }
        }
    }
}

// MARK: - Rain

struct RainView: View {
    @EnvironmentObject var state: AppState
    @State private var sel = 0

    var body: some View {
        let u = state.unit
        let f = state.forecast
        let d = f.flatMap { sel < $0.daily.count ? $0.daily[sel] : nil }
        DetailScroll {
            RainGauge(level: Double(d?.precipChance ?? 0) / 100)
        } content: {
            PageTitle(text: "Rain")
            DetailRow(label: "Chance", value: d.map { "\($0.precipChance)%" } ?? "--", highlighted: true)
            DetailRow(label: "Amount", value: d.map { u.precip($0.precipSum) } ?? "--")
            DetailRow(label: "High", value: d.map { "\(u.temp($0.high))°" } ?? "--")
            DetailRow(label: "Low", value: d.map { "\(u.temp($0.low))°" } ?? "--")
            DetailRow(label: "Outlook", value: d?.condition.title ?? "--")

            if let f, !f.daily.isEmpty {
                Chart {
                    ForEach(Array(f.daily.enumerated()), id: \.offset) { i, day in
                        BarMark(x: .value("Day", i), y: .value("Chance", day.precipChance), width: .fixed(12))
                            .foregroundStyle(state.skin.rain.opacity(i == sel ? 1 : 0.45))
                            .cornerRadius(4)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in AxisValueLabel().font(.mono(10)).foregroundStyle(state.skin.muted) } }
                .frame(height: 110).padding(.top, 18).padding(.horizontal, 8)
                DayPicker(selected: $sel)

                let next = Array(f.hourly.filter { $0.time >= Date().addingTimeInterval(-3600) }.prefix(24))
                if !next.isEmpty {
                    Text("NEXT 24 HOURS").font(.mono(11)).tracking(1.5).foregroundStyle(state.skin.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 22)
                    Chart(next) { h in
                        AreaMark(x: .value("Time", h.time), y: .value("Chance", h.precipChance))
                            .foregroundStyle(state.skin.rain.opacity(0.35)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", h.time), y: .value("Chance", h.precipChance))
                            .foregroundStyle(state.skin.rain).interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()).font(.mono(10)).foregroundStyle(state.skin.muted) } }
                    .chartYAxis(.hidden)
                    .frame(height: 90).padding(.horizontal, 8)
                }
            }
        }
    }
}

struct RainGauge: View {
    @EnvironmentObject var state: AppState
    let level: Double

    var body: some View {
        Canvas { ctx, size in
            let w = min(size.width * 0.5, 160.0), h = size.height * 0.8
            let x0 = (size.width - w) / 2, y0 = size.height * 0.08, inset = w * 0.12
            func glass(_ top: CGFloat) -> Path {
                let k = (top - y0) / h
                var p = Path()
                p.move(to: CGPoint(x: x0 + inset * k, y: top)); p.addLine(to: CGPoint(x: x0 + w - inset * k, y: top))
                p.addLine(to: CGPoint(x: x0 + w - inset, y: y0 + h)); p.addLine(to: CGPoint(x: x0 + inset, y: y0 + h)); p.closeSubpath()
                return p
            }
            let skin = state.skin
            ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - w * 0.75, y: y0 + h - 4, width: w * 1.5, height: 16)), with: .color(.black.opacity(0.25)))
            ctx.fill(glass(y0), with: .linearGradient(Gradient(colors: [Color(hex: skin.cloudHex), Color(hex: skin.cloudHex).opacity(0.6), .black.opacity(0.6)]),
                                                     startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x0 + w, y: 0)))
            let top = y0 + h * (1 - CGFloat(min(max(level, 0), 1)))
            ctx.fill(glass(top), with: .color(skin.rain.opacity(0.85)))
            ctx.stroke(Path(ellipseIn: CGRect(x: x0, y: y0 - 9, width: w, height: 18)), with: .color(skin.muted), lineWidth: 3)
            for i in 1...4 {
                let y = y0 + h * CGFloat(i) / 5
                var p = Path(); p.move(to: CGPoint(x: x0 + w - inset * (y - y0) / h - 2, y: y)); p.addLine(to: CGPoint(x: x0 + w - inset * (y - y0) / h + 12, y: y))
                ctx.stroke(p, with: .color(skin.ink.opacity(0.5)), lineWidth: 2)
            }
        }
    }
}

// MARK: - Sun

struct SunView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            let f = state.forecast
            let today = f?.daily.first
            let rise = today?.sunrise, set = today?.sunset
            let now = tl.date
            let frac: Double? = (rise != nil && set != nil) ? now.timeIntervalSince(rise!) / set!.timeIntervalSince(rise!) : nil
            let alt = f.map { Astronomy.sunAltitude(latitude: $0.place.latitude, longitude: $0.place.longitude, at: now) }
            let up = (alt ?? -1) > -0.8
            let noon = (rise != nil && set != nil) ? rise!.addingTimeInterval(set!.timeIntervalSince(rise!) / 2) : nil
            let daylight = (rise != nil && set != nil) ? set!.timeIntervalSince(rise!) : nil

            DetailScroll {
                SunArc(fraction: frac, up: up, riseText: state.time(rise), setText: state.time(set))
            } content: {
                PageTitle(text: "Sun")
                DetailRow(label: "Sunrise", value: state.time(rise), highlighted: !up)
                DetailRow(label: "Sunset", value: state.time(set), highlighted: up)
                DetailRow(label: "Solar noon", value: state.time(noon))
                DetailRow(label: "Daylight", value: daylight.map { "\(Int($0) / 3600)H \(String(format: "%02d", Int($0) % 3600 / 60))M" } ?? "--")
                DetailRow(label: "Sun height", value: alt.map { "\(Int($0.rounded()))°" } ?? "--")
                DetailRow(label: "UV max today", value: today?.uvMax.map { String(Int($0.rounded())) } ?? "--")

                HStack(spacing: 0) {
                    ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                        VStack(spacing: 3) {
                            Text(state.dayLabel(d, index: i)).foregroundStyle(state.skin.muted)
                            Text(state.time(d.sunset).replacingOccurrences(of: " PM", with: "").replacingOccurrences(of: " AM", with: ""))
                            Text("SET").foregroundStyle(state.skin.muted)
                        }
                        .font(.mono(10)).lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 18)
            }
        }
    }
}

struct SunArc: View {
    @EnvironmentObject var state: AppState
    let fraction: Double?
    let up: Bool
    let riseText: String
    let setText: String

    var body: some View {
        Canvas { ctx, size in
            let skin = state.skin
            let r = min(size.width * 0.4, 150.0), c = CGPoint(x: size.width / 2, y: size.height * 0.78)
            var arc = Path(); arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(arc, with: .color(skin.line), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
            var horizon = Path(); horizon.move(to: CGPoint(x: c.x - r - 30, y: c.y)); horizon.addLine(to: CGPoint(x: c.x + r + 30, y: c.y))
            ctx.stroke(horizon, with: .color(skin.muted), lineWidth: 2)

            let f = min(max(fraction ?? 0, 0), 1)
            let a = CGFloat.pi * CGFloat(1 - f)
            let pos = up ? CGPoint(x: c.x + cos(a) * r, y: c.y - sin(a) * r)
                         : CGPoint(x: (fraction ?? 0) > 1 ? c.x + r : c.x - r, y: c.y + 26)
            if up {
                var done = Path(); done.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .radians(Double.pi + Double.pi * f), clockwise: false)
                ctx.stroke(done, with: .color(skin.ink), lineWidth: 3)
            }
            ctx.opacity = up ? 1 : 0.35
            ctx.fill(Path(ellipseIn: CGRect(x: pos.x - 24, y: pos.y - 24, width: 48, height: 48)), with: .color(skin.sun))
            ctx.opacity = 1
            ctx.draw(Text(riseText).font(.mono(11)).foregroundColor(skin.muted), at: CGPoint(x: c.x - r, y: c.y + (up ? 22 : 62)))
            ctx.draw(Text(setText).font(.mono(11)).foregroundColor(skin.muted), at: CGPoint(x: c.x + r, y: c.y + (up ? 22 : 62)))
        }
    }
}

// MARK: - Moon

struct MoonView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { tl in
            let age = Astronomy.moonAge(tl.date)
            let fmt: (Date) -> String = { d in
                let f = DateFormatter(); f.dateFormat = "MMM d"; f.timeZone = state.forecast?.timeZone; return f.string(from: d).uppercased()
            }
            DetailScroll {
                MoonDisc(age: age, lit: state.skin.moon, dark: Color(hex: state.skin.cloudHex))
                    .frame(width: 220, height: 220)
                    .shadow(color: state.skin.moon.opacity(0.15), radius: 30)
            } content: {
                PageTitle(text: "Moon")
                DetailRow(label: "Phase", value: Astronomy.phaseName(age: age), highlighted: true)
                DetailRow(label: "Illumination", value: "\(Int((Astronomy.illumination(age: age) * 100).rounded()))%")
                DetailRow(label: "Moon age", value: String(format: "%.1f DAYS", age))
                DetailRow(label: "Next full", value: fmt(Astronomy.next(targetAge: Astronomy.synodicMonth / 2, from: tl.date)))
                DetailRow(label: "Next new", value: fmt(Astronomy.next(targetAge: 0, from: tl.date)))

                HStack(spacing: 0) {
                    ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                        VStack(spacing: 6) {
                            Text(state.dayLabel(d, index: i)).font(.mono(10)).foregroundStyle(state.skin.muted)
                                .lineLimit(1).minimumScaleFactor(0.7)
                            MoonDisc(age: Astronomy.moonAge(d.date.addingTimeInterval(21 * 3600)), lit: state.skin.moon, dark: state.skin.line)
                                .frame(width: 26, height: 26)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 18)
            }
        }
    }
}
