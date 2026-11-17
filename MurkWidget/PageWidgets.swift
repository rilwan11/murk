import WidgetKit
import SwiftUI

// One widget per page: Rain next hour, Wind and air, Daylight, Moon. They follow the app's city.

struct FollowingProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, forecast: .sample, unit: SharedStore.unit, skin: SharedStore.skin)
    }
    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await WidgetLoader.load((nil, .sky))) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task {
            let first = await WidgetLoader.load((nil, .sky))
            let entries = (0..<4).map { i -> WeatherEntry in
                let at = first.date.addingTimeInterval(Double(i) * 15 * 60)
                return WeatherEntry(date: at, forecast: first.forecast?.rolled(to: at),
                                    unit: first.unit, skin: first.skin, reason: first.reason)
            }
            completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }
}

/// The frame every page widget shares: Murk glass on full color, system glass on Clear and Tinted, a link to its page.
struct PageWidgetFrame<Content: View>: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry
    let link: String
    @ViewBuilder var content: (Forecast) -> Content

    var body: some View {
        let accented = mode != .fullColor
        // The same smoked navy glass as the main widget, so they sit together on a home screen.
        let sky: Sky? = nil
        let p: Palette = .onGlass
        let isHome = [.systemSmall, .systemMedium, .systemLarge].contains(family)
        Group {
            if let f = entry.forecast { content(f) } else { EmptyWidget(reason: entry.reason) }
        }
        .foregroundStyle(p.ink)
        .overlay(alignment: .topTrailing) {
            if isHome, let f = entry.forecast { FreshnessBadge(fetchedAt: f.fetchedAt, now: entry.date) }
        }
        .environment(\.widgetPalette, p)
        .environment(\.widgetSky, sky)
        .containerBackground(for: .widget) {
            // Clear and Tinted home screens: no fill at all, so the system glass shows the wallpaper
            // like every other widget (a solid fill gets tinted into a flat slab there).
            if accented { Color.clear } else { GlassSurface() }
        }
        .widgetURL(URL(string: link))
    }
}

private struct WidgetHeader: View {
    @Environment(\.widgetPalette) private var pal
    let icon: String
    let title: String
    let place: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy, design: .monospaced))
            Spacer(minLength: 2)
            Text(place).font(.system(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(pal?.muted ?? .secondary)
        }
        .widgetAccentable()
    }
}

// MARK: - Rain next hour

struct MurkRainWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkRain", provider: FollowingProvider()) { entry in
            PageWidgetFrame(entry: entry, link: "murk://rain") { f in RainWidgetView(f: f, u: entry.unit, now: entry.date) }
        }
        .configurationDisplayName("Murk Rain")
        .description("When rain starts or stops, with the next few hours as bars.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct RainWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, u: TempUnit, now: Date

    /// 15-minute bars when the app shared them, otherwise the next 12 hours of chance.
    private var bars: [Double] {
        let q = f.minutely.filter { $0.time.addingTimeInterval(900) > now }.prefix(12)
        if q.count >= 8, q.contains(where: { $0.precip >= 0.1 }) {
            let top = max(1, q.map(\.precip).max() ?? 1)
            return q.map { min(1, $0.precip / top) }
        }
        return f.hourly.filter { $0.time.addingTimeInterval(3600) > now }.prefix(12).map { Double($0.precipChance) / 100 }
    }

    var body: some View {
        let v = Verdicts.rain(f, now: now, unit: u)
        let values = bars
        if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(v.line).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                barsView(values, height: 18)
            }
            .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "cloud.rain.fill", title: String(localized: "Rain"), place: f.place.name)
                Text(v.big).font(.system(size: family == .systemSmall ? 34 : 40, weight: .black).width(.compressed))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(v.line).font(.system(size: 12, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                barsView(values, height: family == .systemSmall ? 26 : 34)
            }
        }
    }

    private func barsView(_ values: [Double], height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 2)
                    .fill(v > 0.05 ? Color(hex: 0x3EA0FF) : (pal?.line ?? .gray))
                    .frame(height: max(2, CGFloat(v) * height))
                    .widgetAccentable()
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}

// MARK: - Wind and air

struct MurkAirWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkAir", provider: FollowingProvider()) { entry in
            PageWidgetFrame(entry: entry, link: "murk://air") { f in AirWidgetView(f: f, u: entry.unit, now: entry.date) }
        }
        .configurationDisplayName("Murk Wind & Air")
        .description("Wind speed and direction, and air quality.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct AirWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, u: TempUnit, now: Date

    var body: some View {
        let v = Verdicts.wind(f, at: nil, now: now, unit: u)
        let from = f.current.windDirection ?? 0
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "location.north.fill").font(.system(size: 12, weight: .bold)).rotationEffect(.degrees(from + 180))
                    Text(v.big).font(.system(size: 20, weight: .black))
                    Text(u == .fahrenheit ? "MPH" : "KM/H").font(.system(size: 8, weight: .bold))
                }
            }
            .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "wind", title: String(localized: "Wind"), place: f.place.name)
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle().stroke(pal?.line ?? .gray, lineWidth: 2)
                        Image(systemName: "location.north.fill").font(.system(size: 20, weight: .bold))
                            .rotationEffect(.degrees(from + 180))
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(v.big).font(.system(size: 34, weight: .black).width(.compressed))
                        Text(v.unit.uppercased()).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(pal?.muted ?? .secondary)
                    }
                }
                Text(v.line).font(.system(size: 11, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let aqi = f.aqi {
                    HStack(spacing: 5) {
                        Circle().fill(Color(hex: Verdicts.aqiHex(aqi))).frame(width: 8, height: 8)
                        Text(String(localized: "AQI \(aqi) · \(Verdicts.aqiWord(aqi))")).font(.system(size: 10, weight: .bold)).lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Daylight

struct MurkDaylightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkDaylight", provider: FollowingProvider()) { entry in
            PageWidgetFrame(entry: entry, link: "murk://sun") { f in DaylightWidgetView(f: f, now: entry.date) }
        }
        .configurationDisplayName("Murk Daylight")
        .description("Daylight left as a ring, and the next sunrise or sunset.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct DaylightWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, now: Date

    var body: some View {
        let d = Verdicts.sunDay(latitude: f.place.latitude, longitude: f.place.longitude, day: now, timeZone: f.timeZone)
        let fraction: Double = {
            guard let r = d.sunrise, let s = d.sunset, s > r else { return 0 }
            return min(1, max(0, now.timeIntervalSince(r) / s.timeIntervalSince(r)))
        }()
        let v = Verdicts.sun(f, now: now)
        if family == .accessoryCircular {
            Gauge(value: fraction) {
                Image(systemName: "sun.max.fill")
            } currentValueLabel: {
                Text(v.big).font(.system(size: 11, weight: .bold)).minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(icon: "sun.max.fill", title: String(localized: "Daylight"), place: f.place.name)
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(pal?.line ?? .gray, lineWidth: 7)
                        Circle().trim(from: 0, to: CGFloat(fraction))
                            .stroke(Color(hex: 0xFFC14D), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .widgetAccentable()
                        Image(systemName: fraction > 0 && fraction < 1 ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(v.big).font(.system(size: 26, weight: .black).width(.compressed)).lineLimit(1).minimumScaleFactor(0.6)
                        Text(v.unit.uppercased()).font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(pal?.muted ?? .secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text(v.line).font(.system(size: 11, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Moon

struct MurkMoonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkMoon", provider: FollowingProvider()) { entry in
            PageWidgetFrame(entry: entry, link: "murk://moon") { f in MoonWidgetView(f: f, now: entry.date, skin: entry.skin) }
        }
        .configurationDisplayName("Murk Moon")
        .description("Tonight's real moon phase and how much of it is lit.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct MoonWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, now: Date, skin: Skin

    var body: some View {
        let age = Astronomy.moonAge(now)
        let k = Int((Astronomy.illumination(age: age) * 100).rounded())
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    fullColorImage(MoonImage.image(age: age, points: 28, tint: 0xFFFFFF)).frame(width: 28, height: 28)
                    Text("\(k)%").font(.system(size: 11, weight: .bold))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(icon: "moon.fill", title: String(localized: "Moon"), place: f.place.name)
                HStack {
                    Spacer()
                    fullColorImage(MoonImage.image(age: age, points: 72, tint: skin.moonHex)).frame(width: 72, height: 72)
                        .shadow(color: .white.opacity(0.15 + 0.25 * Double(k) / 100), radius: 10)
                    Spacer()
                }
                Spacer(minLength: 0)
                Text("\(k)% · \(Astronomy.phaseName(age: age))").font(.system(size: 13, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                Text(Verdicts.moon(f, now: now).line).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(pal?.muted ?? .secondary).lineLimit(2).minimumScaleFactor(0.8)
            }
        }
    }
}
