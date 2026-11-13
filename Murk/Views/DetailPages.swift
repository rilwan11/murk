import SwiftUI
import Charts

// MARK: - Shared day picker

struct DayPicker: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Binding var selected: Int
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        HStack(spacing: 0) {
            ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                Text(state.dayLabel(d, index: i))
                    .font(.mono(10)).tracking(0.5).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(i == selected ? p.onInk : p.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(Capsule().fill(p.ink.opacity(i == selected ? 1 : 0)).padding(.horizontal, 2))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { selected = i }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
            }
        }
        .padding(.horizontal, 6).padding(.top, 6)
    }
}

/// Section caption like "NEXT 24 HOURS".
struct SectionLabel: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let text: String
    var body: some View {
        Text(text).font(.mono(11)).tracking(1.5).foregroundStyle(Palette(skin: state.skin, sky: sky).muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.top, 4)
    }
}

/// Page layout: big art on the sky, the title, then frosted cards.
struct DetailScroll<Art: View, Content: View>: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @ViewBuilder var art: Art
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                art.frame(height: 300).padding(.top, 30)
                VStack(spacing: 12) { content }.detailPage()
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 60)
        }
        .foregroundStyle(Palette(skin: state.skin, sky: sky).ink)
    }
}

// MARK: - Air

struct AirView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @State private var sel = 0
    private var p: Palette { Palette(skin: state.skin, sky: sky) }

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
            GlassCard {
            DetailRow(label: today ? "Wind speed" : "Max wind", value: ((today ? f?.current.windSpeed : d?.windMax)).map(u.wind) ?? "--", highlighted: true)
            DetailRow(label: today ? "Wind gust" : "Max gust", value: ((today ? f?.current.windGust : d?.gustMax)).map(u.wind) ?? "--")
            DetailRow(label: "Wind direction", value: today ? (f?.current.windDirection?.compassDirection ?? "--") : "--")
            DetailRow(label: "Humidity", value: today ? (f?.current.humidity.map { "\(Int($0.rounded()))%" } ?? "--") : "--")
            DetailRow(label: "Pressure", value: today ? (f?.current.pressure.map(u.pressure) ?? "--") : "--")
            DetailRow(label: "Visibility", value: today ? (f?.current.visibility.map(u.visibility) ?? "--") : "--")
            DetailRow(label: "AQI", value: today ? (f?.aqi.map { "\($0) \(aqiLabel($0))" } ?? "--") : "--")
            DetailRow(label: today ? "UV now" : "UV max", value: ((today ? f?.current.uvIndex : d?.uvMax)).map { String(Int($0.rounded())) } ?? "--")
            }

            if let f, !f.daily.isEmpty {
                GlassCard {
                Chart {
                    ForEach(Array(f.daily.enumerated()), id: \.offset) { i, day in
                        if let g = day.gustMax {
                            LineMark(x: .value("Day", i), y: .value("Wind", u.windValue(g)), series: .value("S", "Gust"))
                                .foregroundStyle(p.muted).lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4])).interpolationMethod(.catmullRom)
                        }
                        if let w = day.windMax {
                            AreaMark(x: .value("Day", i), y: .value("Wind", u.windValue(w)))
                                .foregroundStyle(LinearGradient(colors: [p.ink.opacity(0.28), p.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Day", i), y: .value("Wind", u.windValue(w)), series: .value("S", "Wind"))
                                .foregroundStyle(p.ink).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round)).interpolationMethod(.catmullRom)
                        }
                    }
                    RuleMark(x: .value("Day", sel)).foregroundStyle(p.line).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing) { _ in AxisValueLabel().font(.mono(10)).foregroundStyle(p.muted) } }
                .frame(height: 140).padding(.top, 8).padding(.horizontal, 10)
                DayPicker(selected: $sel)
                Note(text: "Solid: max wind · dashed: max gust (\(u.windLabel))")
                }
            }
        }
    }
}

/// Spinning cup anemometer drawn in fake 3D; spins faster with more wind and points into the wind.
struct Anemometer: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let speedKmh: Double
    let direction: Double?

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let spin = CGFloat(t * max(0.4, speedKmh * 0.12))
                let cx = size.width / 2, top = size.height * 0.28, R = min(size.width * 0.32, 120.0), tilt: CGFloat = 0.34
                let skin = state.skin
                let p = Palette(skin: skin, sky: sky)
                // Brushed metal: bright on a sunny sky, the skin's cloud tone otherwise.
                let dark = p.bright && sky != nil ? Color(hex: 0x51627A) : Color(hex: skin.cloudHex)
                let lit = p.bright && sky != nil ? Color.white : Color(hex: skin.cloudHex).opacity(0.65)

                // shadow, pole, compass ring
                ctx.fill(Path(ellipseIn: CGRect(x: cx - 70, y: size.height - 22, width: 140, height: 16)), with: .color(.black.opacity(0.25)))
                ctx.fill(Path(roundedRect: CGRect(x: cx - 4, y: top, width: 8, height: size.height - top - 16), cornerRadius: 3), with: .color(dark))
                let ringY = size.height * 0.62
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - R * 1.25, y: ringY - R * 1.25 * tilt, width: R * 2.5, height: R * 2.5 * tilt)), with: .color(p.line), lineWidth: 4)
                for (label, a) in [("N", -90.0), ("E", 0.0), ("S", 90.0), ("W", 180.0)] {
                    let r = CGFloat(a) * .pi / 180
                    ctx.draw(Text(label).font(.mono(11)).foregroundColor(p.muted),
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
    @Environment(\.sky) private var sky
    @State private var sel = 0
    private var p: Palette { Palette(skin: state.skin, sky: sky) }

    var body: some View {
        let u = state.unit
        let f = state.forecast
        let d = f.flatMap { sel < $0.daily.count ? $0.daily[sel] : nil }
        DetailScroll {
            RainGauge(level: Double(d?.precipChance ?? 0) / 100)
        } content: {
            PageTitle(text: "Rain")
            GlassCard {
            DetailRow(label: "Chance", value: d.map { "\($0.precipChance)%" } ?? "--", highlighted: true)
            DetailRow(label: "Amount", value: d.map { u.precip($0.precipSum) } ?? "--")
            DetailRow(label: "High", value: d.map { "\(u.temp($0.high))°" } ?? "--")
            DetailRow(label: "Low", value: d.map { "\(u.temp($0.low))°" } ?? "--")
            DetailRow(label: "Outlook", value: d?.condition.title ?? "--")
            }

            if let f, !f.daily.isEmpty {
                GlassCard {
                Chart {
                    ForEach(Array(f.daily.enumerated()), id: \.offset) { i, day in
                        BarMark(x: .value("Day", i), y: .value("Chance", day.precipChance), width: .fixed(14))
                            .foregroundStyle(LinearGradient(colors: [Color(hex: 0x7CC4FF), state.skin.rain], startPoint: .top, endPoint: .bottom)
                                .opacity(i == sel ? 1 : 0.45))
                            .cornerRadius(5)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) { _ in AxisValueLabel().font(.mono(10)).foregroundStyle(p.muted) } }
                .frame(height: 110).padding(.top, 8).padding(.horizontal, 10)
                DayPicker(selected: $sel)
                }

                let next = Array(f.hourly.filter { $0.time >= Date().addingTimeInterval(-3600) }.prefix(24))
                if !next.isEmpty {
                    GlassCard {
                    SectionLabel(text: "NEXT 24 HOURS")
                    Chart(next) { h in
                        AreaMark(x: .value("Time", h.time), y: .value("Chance", h.precipChance))
                            .foregroundStyle(state.skin.rain.opacity(0.35)).interpolationMethod(.catmullRom)
                        LineMark(x: .value("Time", h.time), y: .value("Chance", h.precipChance))
                            .foregroundStyle(state.skin.rain).interpolationMethod(.catmullRom)
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()).font(.mono(10)).foregroundStyle(p.muted) } }
                    .chartYAxis(.hidden)
                    .frame(height: 90).padding(.horizontal, 10).padding(.bottom, 4)
                    }
                }
            }
        }
    }
}

struct RainGauge: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
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
            let p = Palette(skin: skin, sky: sky)
            let sunny = sky != nil && p.bright
            ctx.fill(Path(ellipseIn: CGRect(x: size.width / 2 - w * 0.75, y: y0 + h - 4, width: w * 1.5, height: 16)), with: .color(.black.opacity(0.2)))
            // Glass: a clear tube with a bright edge on one side.
            let g0 = sunny ? Color.white.opacity(0.55) : Color(hex: skin.cloudHex)
            ctx.fill(glass(y0), with: .linearGradient(Gradient(colors: [g0, g0.opacity(0.35), .black.opacity(sunny ? 0.12 : 0.6)]),
                                                     startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x0 + w, y: 0)))
            let top = y0 + h * (1 - CGFloat(min(max(level, 0), 1)))
            ctx.fill(glass(top), with: .linearGradient(Gradient(colors: [Color(hex: 0x7CC4FF).opacity(0.95), skin.rain.opacity(0.9)]),
                                                      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: y0 + h)))
            ctx.fill(Path(ellipseIn: CGRect(x: x0 + inset * (top - y0) / h, y: top - 6, width: w - 2 * inset * (top - y0) / h, height: 12)),
                     with: .color(Color(hex: 0xA8D8FF).opacity(level > 0.01 ? 0.9 : 0)))
            var shine = Path(); shine.move(to: CGPoint(x: x0 + w * 0.2, y: y0 + 14)); shine.addLine(to: CGPoint(x: x0 + w * 0.2 + inset * 0.6, y: y0 + h - 14))
            ctx.stroke(shine, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.stroke(Path(ellipseIn: CGRect(x: x0, y: y0 - 9, width: w, height: 18)), with: .color(p.muted), lineWidth: 3)
            for i in 1...4 {
                let y = y0 + h * CGFloat(i) / 5
                var p = Path(); p.move(to: CGPoint(x: x0 + w - inset * (y - y0) / h - 2, y: y)); p.addLine(to: CGPoint(x: x0 + w - inset * (y - y0) / h + 12, y: y))
                ctx.stroke(p, with: .color(Palette(skin: skin, sky: sky).ink.opacity(0.5)), lineWidth: 2)
            }
        }
    }
}

// MARK: - Sun

/// When the sun (or moon) next crosses an altitude, searched minute-by-minute in 6-minute steps.
private func crossing(from start: Date, hours: Double = 24, threshold: Double, rising: Bool,
                      altitude: (Date) -> Double) -> Date? {
    var t = start, prev = altitude(start)
    let end = start.addingTimeInterval(hours * 3600)
    while t < end {
        let n = t.addingTimeInterval(360), a = altitude(n)
        if rising ? (prev < threshold && a >= threshold) : (prev >= threshold && a < threshold) {
            return t.addingTimeInterval(360 * (threshold - prev) / (a - prev))
        }
        prev = a; t = n
    }
    return nil
}

struct SunView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { tl in
            let f = state.forecast
            let today = f?.daily.first
            let rise = today?.sunrise, set = today?.sunset
            let now = tl.date
            let frac: Double? = (rise != nil && set != nil) ? now.timeIntervalSince(rise!) / set!.timeIntervalSince(rise!) : nil
            let altAt: (Date) -> Double = { d in f.map { Astronomy.sunAltitude(latitude: $0.place.latitude, longitude: $0.place.longitude, at: d) } ?? -90 }
            let alt = f.map { _ in altAt(now) }
            let up = (alt ?? -1) > -0.8
            let rising = altAt(now.addingTimeInterval(1800)) >= (alt ?? 0)
            let noon = (rise != nil && set != nil) ? rise!.addingTimeInterval(set!.timeIntervalSince(rise!) / 2) : nil
            let peak = noon.map(altAt)
            let daylight = (rise != nil && set != nil) ? set!.timeIntervalSince(rise!) : nil
            let golden = set.flatMap { s in crossing(from: s.addingTimeInterval(-4 * 3600), hours: 4, threshold: 6, rising: false, altitude: altAt) }

            DetailScroll {
                SunArc(fraction: frac, altitude: alt ?? -10, peak: peak ?? 60, rising: rising,
                       riseText: state.time(rise), setText: state.time(set))
            } content: {
                PageTitle(text: "Sun")
                GlassCard {
                    DetailRow(label: "Sunrise", value: state.time(rise), highlighted: !up)
                    DetailRow(label: "Sunset", value: state.time(set), highlighted: up)
                    DetailRow(label: "Golden hour", value: state.time(golden))
                    DetailRow(label: "Solar noon", value: state.time(noon))
                    DetailRow(label: "Daylight", value: daylight.map { "\(Int($0) / 3600)H \(String(format: "%02d", Int($0) % 3600 / 60))M" } ?? "--")
                    DetailRow(label: "Sun height", value: alt.map { "\(Int($0.rounded()))°" } ?? "--")
                    DetailRow(label: "UV max today", value: today?.uvMax.map { String(Int($0.rounded())) } ?? "--")
                }
                GlassCard {
                    SectionLabel(text: "SUNSET THIS WEEK")
                    SunsetWeek()
                }
            }
        }
    }
}

/// Sunset for each day, each with a little horizon and a sun dipping into it.
private struct SunsetWeek: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        HStack(spacing: 0) {
            ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                VStack(spacing: 4) {
                    Text(state.dayLabel(d, index: i)).foregroundStyle(p.muted)
                    ZStack(alignment: .bottom) {
                        Circle().fill(RadialGradient(colors: [Color(hex: 0xFFD27A), Color(hex: 0xEE4A2A)], center: .center, startRadius: 0, endRadius: 9))
                            .frame(width: 16, height: 16).offset(y: 6).shadow(color: Color(hex: 0xFF6A3A).opacity(0.7), radius: 5)
                        Rectangle().fill(p.ink.opacity(0.5)).frame(width: 26, height: 1.5)
                    }
                    .frame(height: 18).clipped()
                    Text(state.time(d.sunset).replacingOccurrences(of: " PM", with: "").replacingOccurrences(of: " AM", with: ""))
                }
                .font(.mono(10)).lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }
}

/// The day's arc over the horizon: the path glows from dawn orange through noon yellow to dusk red,
/// the passed part is solid, and the sun is a glowing ball in its current color.
struct SunArc: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let fraction: Double?
    let altitude: Double
    let peak: Double
    let rising: Bool
    let riseText: String
    let setText: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            Canvas { ctx, size in
                let p = Palette(skin: state.skin, sky: sky)
                let t = tl.date.timeIntervalSinceReferenceDate
                let r = min(size.width * 0.4, 150.0), c = CGPoint(x: size.width / 2, y: size.height * 0.74)
                let warm = Gradient(stops: [.init(color: Color(hex: 0xFF8F3A), location: 0), .init(color: Color(hex: 0xFFD54D), location: 0.5),
                                            .init(color: Color(hex: 0xEE4028), location: 1)])
                let shade = GraphicsContext.Shading.linearGradient(warm, startPoint: CGPoint(x: c.x - r, y: 0), endPoint: CGPoint(x: c.x + r, y: 0))

                // Dome of light under the arc.
                var dome = Path(); dome.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false); dome.closeSubpath()
                ctx.fill(dome, with: .radialGradient(Gradient(colors: [Color(hex: 0xFFD27A).opacity(altitude > 0 ? 0.22 : 0.06), .clear]),
                                                     center: c, startRadius: 0, endRadius: r))

                var arc = Path(); arc.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                ctx.stroke(arc, with: shade, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 7]))
                let f = min(max(fraction ?? 0, 0), 1)
                let up = altitude > -0.8
                if up {
                    var done = Path(); done.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .radians(Double.pi + Double.pi * f), clockwise: false)
                    ctx.stroke(done, with: shade, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                // Hour ticks along the arc.
                for k in 1..<6 {
                    let a = CGFloat.pi * CGFloat(k) / 6
                    var tk = Path()
                    tk.move(to: CGPoint(x: c.x - cos(a) * (r - 7), y: c.y - sin(a) * (r - 7)))
                    tk.addLine(to: CGPoint(x: c.x - cos(a) * (r + 7), y: c.y - sin(a) * (r + 7)))
                    ctx.stroke(tk, with: .color(p.line), lineWidth: 2)
                }

                // Horizon with a soft glow.
                var horizon = Path(); horizon.move(to: CGPoint(x: c.x - r - 34, y: c.y)); horizon.addLine(to: CGPoint(x: c.x + r + 34, y: c.y))
                ctx.stroke(horizon, with: .color(p.ink.opacity(0.65)), lineWidth: 2)

                // Sun: on the arc while up; below the horizon at night, at the side it set/rises.
                let a = CGFloat.pi * CGFloat(1 - f)
                let pos = up ? CGPoint(x: c.x + cos(a) * r, y: c.y - sin(a) * r)
                             : CGPoint(x: (fraction ?? 0) > 1 ? c.x + r : c.x - r, y: c.y + 30)
                let col = Color(uiColor: WeatherScene.sunColor(altitude: max(altitude, 0), rising: rising))
                let pulse = 1 + 0.04 * CGFloat(sin(t * 1.3))
                ctx.drawLayer { l in
                    if !up { l.opacity = 0.35 }
                    let R: CGFloat = 26
                    l.fill(Path(ellipseIn: CGRect(x: pos.x - R * 3 * pulse, y: pos.y - R * 3 * pulse, width: R * 6 * pulse, height: R * 6 * pulse)),
                           with: .radialGradient(Gradient(colors: [col.opacity(0.45), col.opacity(0.12), .clear]), center: pos, startRadius: R * 0.8, endRadius: R * 3 * pulse))
                    l.fill(Path(ellipseIn: CGRect(x: pos.x - R, y: pos.y - R, width: 2 * R, height: 2 * R)),
                           with: .radialGradient(Gradient(stops: [.init(color: .white, location: 0), .init(color: Color(hex: 0xFFF6D8), location: 0.25),
                                                                  .init(color: col, location: 0.8), .init(color: col.opacity(0.85), location: 1)]),
                                                 center: CGPoint(x: pos.x - R * 0.15, y: pos.y - R * 0.15), startRadius: 0, endRadius: R))
                }
                let labelY = c.y + (up ? 22 : 62)
                ctx.draw(Text(Image(systemName: "sunrise.fill")).font(.system(size: 13)).foregroundColor(Color(hex: 0xFF9A3C)), at: CGPoint(x: c.x - r, y: labelY - 0))
                ctx.draw(Text(riseText).font(.mono(11)).foregroundColor(p.muted), at: CGPoint(x: c.x - r, y: labelY + 17))
                ctx.draw(Text(Image(systemName: "sunset.fill")).font(.system(size: 13)).foregroundColor(Color(hex: 0xEE4A2A)), at: CGPoint(x: c.x + r, y: labelY))
                ctx.draw(Text(setText).font(.mono(11)).foregroundColor(p.muted), at: CGPoint(x: c.x + r, y: labelY + 17))
                if up {
                    ctx.draw(Text("\(Int(altitude.rounded()))°").font(.mono(11)).foregroundColor(p.ink),
                             at: CGPoint(x: pos.x, y: pos.y - 42))
                }
            }
        }
    }
}

// MARK: - Moon

struct MoonView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { tl in
            let age = Astronomy.moonAge(tl.date)
            let k = Astronomy.illumination(age: age)
            let p = Palette(skin: state.skin, sky: sky)
            let tz = state.forecast?.timeZone ?? .current
            let fmt: (Date) -> String = { d in
                let f = DateFormatter(); f.dateFormat = "MMM d"; f.timeZone = tz; return f.string(from: d).uppercased()
            }
            let lat = state.forecast?.place.latitude, lon = state.forecast?.place.longitude
            let altAt: (Date) -> Double = { d in (lat != nil && lon != nil) ? NowView.moonAltitude(lat!, lon!, d) : -90 }
            let moonrise = crossing(from: tl.date, threshold: 0, rising: true, altitude: altAt)
            let moonset = crossing(from: tl.date, threshold: 0, rising: false, altitude: altAt)
            let moonUp = altAt(tl.date) > 0
            DetailScroll {
                ZStack {
                    // Glow only as bright as the lit part.
                    Circle().fill(RadialGradient(colors: [state.skin.moon.opacity(0.10 + 0.25 * k), .clear], center: .center, startRadius: 90, endRadius: 170))
                        .frame(width: 340, height: 340)
                    MoonOrbView(age: age, tint: state.skin.moonHex)
                        .frame(width: 280, height: 280)
                        .noPageSwipe(page: 4)
                }
            } content: {
                PageTitle(text: "Moon")
                GlassCard {
                    DetailRow(label: "Phase", value: Astronomy.phaseName(age: age), highlighted: true)
                    DetailRow(label: "Illumination", value: "\(Int((k * 100).rounded()))%")
                    DetailRow(label: moonUp ? "Moonset" : "Moonrise", value: state.time(moonUp ? moonset : moonrise))
                    DetailRow(label: moonUp ? "Next rise" : "Then sets", value: state.time(moonUp ? moonrise : moonset))
                    DetailRow(label: "Moon age", value: String(format: "%.1f DAYS", age))
                    DetailRow(label: "Next full", value: fmt(Astronomy.next(targetAge: Astronomy.synodicMonth / 2, from: tl.date)))
                    DetailRow(label: "Next new", value: fmt(Astronomy.next(targetAge: 0, from: tl.date)))
                }
                GlassCard {
                    SectionLabel(text: "PHASES THIS WEEK")
                    HStack(spacing: 0) {
                        ForEach(Array(state.days.enumerated()), id: \.offset) { i, d in
                            let a = Astronomy.moonAge(d.date.addingTimeInterval(21 * 3600))
                            VStack(spacing: 6) {
                                Text(state.dayLabel(d, index: i)).font(.mono(10)).foregroundStyle(p.muted)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                                Image(uiImage: MoonImage.image(age: a, points: 30, tint: state.skin.moonHex))
                                    .resizable().frame(width: 30, height: 30)
                                    .background(Circle().fill(Color.black.opacity(0.35)).padding(-1))
                                Text("\(Int((Astronomy.illumination(age: a) * 100).rounded()))%").font(.mono(9)).foregroundStyle(p.muted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                }
                GlassCard {
                    SectionLabel(text: "THIS MONTH")
                    MoonMonth(age: age)
                }
                Note(text: "Drag the moon to turn it")
            }
        }
    }
}

/// The whole lunar cycle as a strip, with a marker at tonight.
private struct MoonMonth: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let age: Double
    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let n = 15
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { i in
                        let a = Double(i) / Double(n - 1) * Astronomy.synodicMonth
                        Image(uiImage: MoonImage.image(age: a, points: 18, tint: state.skin.moonHex))
                            .resizable().frame(width: 18, height: 18)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                            .frame(maxWidth: .infinity)
                    }
                }
                let x = CGFloat(age / Astronomy.synodicMonth) * (w - w / CGFloat(n)) + w / CGFloat(n) / 2
                Capsule().fill(p.ink).frame(width: 3, height: 10).offset(x: x - 1.5, y: 24)
                Text("TONIGHT").font(.mono(9)).foregroundStyle(p.ink)
                    .fixedSize().offset(x: min(max(x - 22, 0), w - 44), y: 36)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 6).padding(.vertical, 6)
    }
}
