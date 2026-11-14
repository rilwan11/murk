import SwiftUI

struct MoonView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Environment(\.pageActive) private var active

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { tl in
            content(now: tl.date)
        }
    }

    private func moment(_ now: Date) -> Date { now.addingTimeInterval(state.moonDayOffset * 86400) }

    private func verdict(_ f: Forecast?, now: Date) -> Verdict? {
        guard let f else { return nil }
        if abs(state.moonDayOffset) < 0.01 { return Verdicts.moon(f, now: now) }
        let t = moment(now)
        let age = Astronomy.moonAge(t)
        let k = Int((Astronomy.illumination(age: age) * 100).rounded())
        var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.wide).month(.abbreviated).day()
        style.timeZone = f.timeZone
        let days = Int(state.moonDayOffset.rounded())
        let when = days > 0 ? String(localized: "in \(days) days") : String(localized: "\(-days) days ago")
        return Verdict(big: "\(k)", unit: "% · " + Astronomy.phaseName(age: age), line: "\(t.formatted(style)), \(when)")
    }

    @ViewBuilder private func content(now: Date) -> some View {
        let f = state.forecast
        let t = moment(now)
        let age = Astronomy.moonAge(t)
        let k = Astronomy.illumination(age: age)
        PageScaffold(title: String(localized: "Moon"), page: 4, verdict: verdict(f, now: now), showsSlider: false) {
            ZStack {
                if sky?.bright != true { StarField().opacity(0.9) }
                Circle().fill(RadialGradient(colors: [state.skin.moon.opacity(0.08 + 0.25 * k), .clear], center: .center, startRadius: 80, endRadius: 170))
                    .opacity(sky?.bright == true ? 0 : 1)
                MoonOrbView(age: age, tint: state.skin.moonHex,
                            daySky: sky.flatMap { $0.bright ? Sky.lerp($0.top, $0.mid, 0.45) : nil })
                    .aspectRatio(1, contentMode: .fit)
                    .padding(12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(Text("The moon, \(Int((k * 100).rounded())) percent lit, \(Astronomy.phaseName(age: age))"))
        } extra: {
            MoonDaySlider(offset: $state.moonDayOffset, now: now)
                .padding(.horizontal, 22)
                .noPageSwipe(page: 4)
        } cards: {
            if let f {
                GlassCard {
                    CardTitle(text: String(localized: "Tonight"))
                    TonightBar(forecast: f, now: now)
                }
                GlassCard {
                    CardTitle(text: String(localized: "This month"))
                    MoonCalendar(timeZone: f.timeZone, now: now, selected: t) { date in
                        withAnimation(.easeInOut(duration: 0.4)) { state.moonDayOffset = date.timeIntervalSince(now) / 86400 }
                    }
                }
                GlassCard {
                    CardTitle(text: String(localized: "Coming up"))
                    comingUp(f, now: now)
                }
            }
        } details: {
            if let f { details(f, now: now) }
        }
    }

    @ViewBuilder private func comingUp(_ f: Forecast, now: Date) -> some View {
        let s = Astronomy.synodicMonth
        let events: [(String, Date)] = [
            (String(localized: "First quarter"), Astronomy.next(targetAge: s / 4, from: now)),
            (String(localized: "Full moon"), Astronomy.next(targetAge: s / 2, from: now)),
            (String(localized: "Last quarter"), Astronomy.next(targetAge: s * 3 / 4, from: now)),
            (String(localized: "New moon"), Astronomy.next(targetAge: 0, from: now)),
        ].sorted { $0.1 < $1.1 }
        let cal = Calendar.zoned(f.timeZone)
        ForEach(Array(events.enumerated()), id: \.offset) { _, e in
            let name = e.0 == String(localized: "Full moon") ? "\(e.0) · \(Astronomy.fullMoonName(e.1, calendar: cal))" : e.0
            DetailRow(label: name, value: Self.date(e.1, f.timeZone))
        }
    }

    static func date(_ d: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = tz
        return d.formatted(style).uppercased()
    }

    @ViewBuilder private func details(_ f: Forecast, now: Date) -> some View {
        let pos = Astronomy.moonPosition(latitude: f.place.latitude, longitude: f.place.longitude, at: now)
        let night = Verdicts.moonNight(f, now: now)
        DetailRow(label: String(localized: "Moon age"), value: String(format: "%.1f DAYS", Astronomy.moonAge(now)))
        DetailRow(label: String(localized: "Distance"), value: state.unit == .fahrenheit ? String(format: "%.0f MI", pos.distanceKm * 0.621371) : String(format: "%.0f KM", pos.distanceKm))
        DetailRow(label: String(localized: "Height now"), value: "\(Int(pos.altitude.rounded()))° \(pos.azimuth.compassDirection)")
        DetailRow(label: String(localized: "Next moonrise"), value: state.time(night.rise))
        DetailRow(label: String(localized: "Next moonset"), value: state.time(night.set))
    }
}

/// A quiet, fixed star field behind the moon at night.
private struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 11)
            for _ in 0..<140 {
                let x: CGFloat = CGFloat(rng.next()) * size.width
                let y: CGFloat = CGFloat(rng.next()) * size.height
                let r: CGFloat = 0.4 + CGFloat(rng.next()) * 1.3
                let a: Double = 0.25 + rng.next() * 0.6
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(a)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Drag through four weeks either side of tonight; a tick and a haptic at each quarter, full and new moon.
private struct MoonDaySlider: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    @Binding var offset: Double
    let now: Date
    static let span = 14.0

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                let x = CGFloat((offset + Self.span) / (2 * Self.span)) * w
                ZStack(alignment: .leading) {
                    Capsule().fill(p.line).frame(height: 6)
                    ForEach(-2...2, id: \.self) { k in
                        let d = Double(k) * 7
                        Image(uiImage: MoonImage.image(age: Astronomy.moonAge(now.addingTimeInterval(d * 86400)), points: 16, tint: state.skin.moonHex))
                            .resizable().frame(width: 16, height: 16)
                            .position(x: CGFloat((d + Self.span) / (2 * Self.span)) * w, y: 22)
                    }
                    Circle().fill(Color.white).frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .position(x: min(max(x, 11), w - 11), y: 3)
                }
                .frame(height: 30, alignment: .top)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let t = Double(min(max(v.location.x, 0), w) / w) * 2 * Self.span - Self.span
                    let snapped = (t * 4).rounded() / 4
                    if snapped != offset {
                        let before = Self.quarter(Astronomy.moonAge(now.addingTimeInterval(offset * 86400)))
                        let after = Self.quarter(Astronomy.moonAge(now.addingTimeInterval(snapped * 86400)))
                        if before != after { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                        else if Int(snapped) != Int(offset) { UISelectionFeedbackGenerator().selectionChanged() }
                        offset = snapped
                    }
                })
            }
            .frame(height: 34)
            HStack {
                Text(String(localized: "−2 WEEKS")).font(.mono(9)).foregroundStyle(p.muted)
                Spacer()
                Button(String(localized: "TONIGHT")) { withAnimation(.easeInOut(duration: 0.4)) { offset = 0 } }
                    .font(.mono(10, .bold)).foregroundStyle(abs(offset) < 0.01 ? p.muted : p.ink)
                Spacer()
                Text(String(localized: "+2 WEEKS")).font(.mono(9)).foregroundStyle(p.muted)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Day"))
        .accessibilityValue(Text(abs(offset) < 0.01 ? String(localized: "Tonight") : String(localized: "\(Int(offset.rounded())) days from tonight")))
        .accessibilityAdjustableAction { d in
            switch d {
            case .increment: offset = min(Self.span, offset.rounded() + 1)
            case .decrement: offset = max(-Self.span, offset.rounded() - 1)
            @unknown default: break
            }
        }
    }

    /// Which quarter of the cycle an age is in (0 new … 3 last quarter).
    static func quarter(_ age: Double) -> Int { Int(age / Astronomy.synodicMonth * 4) % 4 }
}

/// Sunset to sunrise: when it's dark, when the moon is up, and how cloudy each hour is.
private struct TonightBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let forecast: Forecast
    let now: Date

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let lat = forecast.place.latitude, lon = forecast.place.longitude
        let today = Verdicts.sunDay(latitude: lat, longitude: lon, day: now, timeZone: forecast.timeZone)
        let tomorrow = Verdicts.sunDay(latitude: lat, longitude: lon, day: now.addingTimeInterval(86400), timeZone: forecast.timeZone)
        let start = (today.sunset ?? now) < now && (tomorrow.sunrise ?? now) > now ? now : (today.sunset ?? now)
        let end = tomorrow.sunrise ?? start.addingTimeInterval(12 * 3600)
        let span = max(3600, end.timeIntervalSince(start))
        let steps = 72
        let up: [Bool] = (0..<steps).map { i in
            Astronomy.moonAltitude(latitude: lat, longitude: lon, at: start.addingTimeInterval(span * Double(i) / Double(steps))) > 0.125
        }
        let hours = forecast.hourly.filter { $0.time >= start.addingTimeInterval(-3600) && $0.time <= end }
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let bw = size.width / CGFloat(steps)
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8), with: .color(Color(hex: 0x0B1430)))
                for (i, u) in up.enumerated() where u {
                    ctx.fill(Path(CGRect(x: CGFloat(i) * bw, y: size.height * 0.35, width: bw + 0.5, height: size.height * 0.3)),
                             with: .color(Color(hex: state.skin.moonHex).opacity(0.85)))
                }
                for h in hours {
                    guard let c = h.cloudCover, c > 10 else { continue }
                    let x0 = CGFloat(h.time.timeIntervalSince(start) / span) * size.width
                    let rect = CGRect(x: x0, y: 0, width: size.width * CGFloat(3600 / span), height: size.height).intersection(CGRect(origin: .zero, size: size))
                    ctx.fill(Path(rect), with: .color(Color.gray.opacity(c / 100 * 0.55)))
                }
            }
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Label(state.time(start), systemImage: "sunset.fill")
                Spacer()
                Label(state.time(end), systemImage: "sunrise.fill")
            }
            .font(.mono(10)).foregroundStyle(p.muted)
            HStack(spacing: 10) {
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color(hex: state.skin.moonHex)).frame(width: 12, height: 6); Text(String(localized: "Moon up")) }
                HStack(spacing: 4) { RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.5)).frame(width: 12, height: 6); Text(String(localized: "Cloud")) }
                Spacer()
            }
            .font(.mono(9)).foregroundStyle(p.muted)
        }
        .padding(.horizontal, 14).padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Verdicts.moon(forecast, now: now).line))
    }
}

/// The month as a calendar, each date with its real phase picture; tap a date to show it.
private struct MoonCalendar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.sky) private var sky
    let timeZone: TimeZone
    let now: Date
    let selected: Date
    var pick: (Date) -> Void

    var body: some View {
        let p = Palette(skin: state.skin, sky: sky)
        let cal = Calendar.zoned(timeZone)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let days = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let lead = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<days).map { cal.date(byAdding: .day, value: $0, to: monthStart) }
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        VStack(spacing: 4) {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s).font(.mono(9)).foregroundStyle(p.muted)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, d in
                    if let d {
                        let night = d.addingTimeInterval(21 * 3600)
                        let age = Astronomy.moonAge(night)
                        let isToday = cal.isDate(d, inSameDayAs: now)
                        let isSel = cal.isDate(d, inSameDayAs: selected)
                        let marker = Self.marker(age)
                        VStack(spacing: 2) {
                            Image(uiImage: MoonImage.image(age: age, points: 24, tint: state.skin.moonHex))
                                .resizable().frame(width: 24, height: 24)
                            Text("\(cal.component(.day, from: d))").font(.mono(9, isToday ? .bold : .regular))
                            Text(marker ?? " ").font(.mono(7)).foregroundStyle(p.muted)
                        }
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 8).stroke(isSel ? p.ink : (isToday ? p.muted : .clear), lineWidth: isSel ? 1.5 : 1))
                        .contentShape(Rectangle())
                        .onTapGesture { pick(night) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("\(Self.dayName(d, timeZone)), \(Astronomy.phaseName(age: age))"))
                        .accessibilityAddTraits(.isButton)
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 4)
    }

    /// FULL / NEW on the night closest to those phases.
    static func marker(_ age: Double) -> String? {
        let s = Astronomy.synodicMonth
        if abs(age - s / 2) < 0.5 { return String(localized: "FULL") }
        if age < 0.5 || age > s - 0.5 { return String(localized: "NEW") }
        return nil
    }

    static func dayName(_ d: Date, _ tz: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).month(.wide).day()
        style.timeZone = tz
        return d.formatted(style)
    }
}
