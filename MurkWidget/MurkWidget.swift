import WidgetKit
import SwiftUI

// MARK: - Timeline

struct WeatherEntry: TimelineEntry {
    let date: Date
    let forecast: Forecast?
    let unit: TempUnit
    let skin: Skin
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WeatherEntry {
        WeatherEntry(date: .now, forecast: .sample, unit: SharedStore.unit, skin: SharedStore.skin)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
        Task {
            let entry = await load()
            // Refresh every 30 minutes (iOS may stretch this to save battery).
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    private func load() async -> WeatherEntry {
        let f = try? await WeatherService().forecast(for: SharedStore.place)
        return WeatherEntry(date: .now, forecast: f, unit: SharedStore.unit, skin: SharedStore.skin)
    }
}

// MARK: - Widget

@main
struct MurkWidgetBundle: WidgetBundle {
    var body: some Widget { MurkWeatherWidget() }
}

struct MurkWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MurkWeather", provider: Provider()) { entry in
            WidgetView(entry: entry)
        }
        .configurationDisplayName("Murk")
        .description("The weather, but moodier.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WeatherEntry

    var body: some View {
        Group {
            if let f = entry.forecast {
                switch family {
                case .systemSmall: SmallView(f: f, u: entry.unit, skin: entry.skin)
                case .systemMedium: MediumView(f: f, u: entry.unit, skin: entry.skin)
                case .systemLarge: LargeView(f: f, u: entry.unit, skin: entry.skin)
                case .accessoryCircular: CircularView(f: f, u: entry.unit)
                case .accessoryRectangular: RectangularView(f: f, u: entry.unit)
                case .accessoryInline: Text("\(entry.unit.temp(f.current.temperature))° \(f.current.condition.title)")
                default: SmallView(f: f, u: entry.unit, skin: entry.skin)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "icloud.slash")
                    Text("No forecast").font(.caption2)
                }
                .foregroundStyle(entry.skin.muted)
            }
        }
        .containerBackground(for: .widget) {
            entry.skin.bg
        }
        .widgetURL(URL(string: "murk://now"))
    }
}

// MARK: - Home screen sizes

private extension Font {
    static func bigTemp(_ size: CGFloat) -> Font { .system(size: size, weight: .black).width(.compressed) }
}

/// The temperature as a sculpted, extruded slab — stacked offset layers for depth,
/// a lit gradient face and a faint highlight edge, like the 3D digits in the app.
struct ExtrudedText: View {
    @Environment(\.widgetRenderingMode) private var mode
    let text: String
    let size: CGFloat
    let skin: Skin

    var body: some View {
        if mode == .fullColor { sculpted } else {
            // Tinted / clear home screens recolor everything, so stacked depth layers turn into a blob.
            Text(text).font(.bigTemp(size)).widgetAccentable()
                .lineLimit(1).minimumScaleFactor(0.5)
        }
    }

    @ViewBuilder private var sculpted: some View {
        let f = Font.bigTemp(size)
        let face = Color(hex: skin.digitHex)
        let depth = 9
        ZStack {
            ForEach(0..<depth, id: \.self) { i in
                let k = CGFloat(depth - i)
                Text(text).font(f)
                    .foregroundStyle(Color.black.opacity(0.55 + 0.04 * Double(i)))
                    .offset(x: k * size * 0.006, y: k * size * 0.010)
            }
            Text(text).font(f)
                .foregroundStyle(LinearGradient(colors: [face.mix(white: 0.30), face.mix(white: 0.06), face, face.mix(white: 0.18)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(text).font(f)
                .foregroundStyle(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                .mask(Text(text).font(f).offset(y: size * 0.012))
                .blendMode(.plusLighter)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

/// The 3D sky rendered by the app (clouds + sun or tonight's moon), with rain or snow streaks.
struct Sky3D: View {
    let code: Int
    let isDay: Bool
    let skin: Skin

    var body: some View {
        let kind = ArtKind(code: code)
        ZStack {
            if let ui = WidgetArt.image(kind, day: isDay, skin: skin) {
                skyImage(ui)
            } else {
                CloudArt(cover: kind.cover, isDay: isDay, skin: skin).padding(10)
            }
            if kind == .rain || kind == .snow {
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 7)
                    let snow = kind == .snow
                    for _ in 0..<(snow ? 26 : 38) {
                        let x = CGFloat(rng.next()) * size.width * 0.8 + size.width * 0.1
                        let y = size.height * (0.62 + CGFloat(rng.next()) * 0.38)
                        if snow {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.85)))
                        } else {
                            var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - 1.5, y: y + 9))
                            ctx.stroke(p, with: .color(skin.rain.opacity(0.9)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        }
                    }
                }
            }
        }
    }
}

@ViewBuilder
private func skyImage(_ ui: UIImage) -> some View {
    if #available(iOS 18.0, *) {
        Image(uiImage: ui).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
    } else {
        Image(uiImage: ui).resizable().scaledToFit()
    }
}

struct SeededRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

/// Cloud above, sculpted temperature tucked underneath — the app's main screen in miniature.
struct HeroStack: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var skySize: CGFloat
    var tempSize: CGFloat

    var body: some View {
        VStack(spacing: -tempSize * 0.32) {
            Sky3D(code: f.current.code, isDay: f.current.isDay, skin: skin)
                .frame(width: skySize, height: skySize * 0.62)
                .clipped()
                .zIndex(1)
            ExtrudedText(text: "\(u.temp(f.current.temperature))", size: tempSize, skin: skin)
        }
    }
}

struct SmallView: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                if f.place.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: 8, weight: .bold)) }
                Text(f.place.name).font(.system(size: 12, weight: .heavy)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(skin.ink)
            .widgetAccentable()
            HeroStack(f: f, u: u, skin: skin, skySize: 132, tempSize: 74)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MediumView: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        HStack(spacing: 10) {
            SmallView(f: f, u: u, skin: skin).frame(width: 140)
            VStack(alignment: .leading, spacing: 6) {
                Text(f.current.condition.title).font(.system(size: 15, weight: .black)).lineLimit(1)
                    .foregroundStyle(skin.ink)
                HStack(spacing: 0) {
                    ForEach(Array(f.daily.dropFirst().prefix(5).enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 4) {
                            Text(weekday(d.date, f.timeZone)).font(.system(size: 9, design: .monospaced)).foregroundStyle(skin.muted)
                            WidgetDayIcon(condition: d.condition, skin: skin)
                            Text("\(u.temp(d.high))").font(.system(size: 14, weight: .heavy))
                            Text("\(u.temp(d.low))").font(.system(size: 14, weight: .heavy)).foregroundStyle(skin.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(skin.ink)
            }
        }
    }
}

struct LargeView: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        let days = Array(f.daily.prefix(5))
        let lo = days.map(\.low).min() ?? 0, hi = days.map(\.high).max() ?? 1
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if f.place.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: 10, weight: .bold)) }
                Text(f.place.name).font(.system(size: 16, weight: .heavy)).lineLimit(1)
            }
            .foregroundStyle(skin.ink)
            HeroStack(f: f, u: u, skin: skin, skySize: 230, tempSize: 118)
                .frame(height: 190)
            Text(f.current.condition.title).font(.system(size: 18, weight: .black)).foregroundStyle(skin.ink)
            Spacer(minLength: 0)
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                HStack(spacing: 10) {
                    Text(i == 0 ? "TODAY" : weekday(d.date, f.timeZone))
                        .font(.system(size: 11, design: .monospaced)).frame(width: 44, alignment: .leading)
                    WidgetDayIcon(condition: d.condition, skin: skin).frame(width: 24)
                    Text("\(u.temp(d.low))").font(.system(size: 13, weight: .heavy)).foregroundStyle(skin.muted).frame(width: 26, alignment: .trailing)
                    GeometryReader { g in
                        let x0 = (d.low - lo) / max(hi - lo, 1), x1 = (d.high - lo) / max(hi - lo, 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(skin.line).frame(height: 5)
                            Capsule().fill(skin.ink).frame(width: max(6, g.size.width * (x1 - x0)), height: 5)
                                .offset(x: g.size.width * x0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    Text("\(u.temp(d.high))").font(.system(size: 13, weight: .heavy)).frame(width: 26, alignment: .trailing)
                }
                .foregroundStyle(skin.ink)
                .frame(height: 20)
            }
        }
    }
}

// MARK: - Lock screen

struct CircularView: View {
    let f: Forecast, u: TempUnit
    var body: some View {
        let today = f.daily.first
        let lo = Double(u.temp(today?.low ?? f.current.temperature)), hi = Double(u.temp(today?.high ?? f.current.temperature))
        let now = Double(u.temp(f.current.temperature))
        Gauge(value: min(max(now, lo), max(hi, lo + 1)), in: lo...max(hi, lo + 1)) {
            Image(systemName: f.current.condition.symbol)
        } currentValueLabel: {
            Text("\(Int(now))°")
        } minimumValueLabel: { Text("\(Int(lo))") } maximumValueLabel: { Text("\(Int(hi))") }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }
}

struct RectangularView: View {
    let f: Forecast, u: TempUnit
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: f.current.condition.symbol)
                Text(f.place.name).fontWeight(.semibold).lineLimit(1)
            }
            .font(.caption)
            Text("\(u.temp(f.current.temperature))° \(f.current.condition.title)").font(.headline).lineLimit(1)
            if let d = f.daily.first {
                Text("H \(u.temp(d.high))° L \(u.temp(d.low))°\(d.precipChance >= 30 ? " · \(d.precipChance)% rain" : "")").font(.caption2)
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Art

/// A small static version of the 3D scene: shaded cloud spheres with the moon or sun behind.
struct CloudArt: View {
    let cover: Double
    let isDay: Bool
    let skin: Skin

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let puffs: [(CGFloat, CGFloat, CGFloat)] = [(0.42, 0.50, 0.26), (0.62, 0.58, 0.22), (0.24, 0.66, 0.19), (0.78, 0.70, 0.15), (0.50, 0.74, 0.18), (0.36, 0.78, 0.14)]
            let count = max(2, Int((Double(puffs.count) * (0.35 + cover * 0.65)).rounded()))
            ZStack {
                orb.frame(width: w * 0.5, height: w * 0.5).position(x: w * 0.68, y: h * 0.3)
                ForEach(0..<count, id: \.self) { i in
                    let p = puffs[i]
                    Circle()
                        .fill(RadialGradient(colors: [Color(hex: skin.cloudHex).opacity(1).mix(white: 0.28), Color(hex: skin.cloudHex), .black],
                                             center: UnitPoint(x: 0.34, y: 0.26), startRadius: 0, endRadius: w * p.2 * 1.6))
                        .frame(width: w * p.2 * 2, height: w * p.2 * 2)
                        .position(x: w * p.0, y: h * p.1)
                }
            }
        }
    }

    @ViewBuilder private var orb: some View {
        if isDay {
            Circle().fill(skin.sun)
        } else {
            MoonDisc(age: Astronomy.moonAge(), lit: skin.moon, dark: .clear)
        }
    }
}

struct WidgetDayIcon: View {
    let condition: Condition
    let skin: Skin
    var body: some View {
        let rainy = condition.precip == .rain
        Image(systemName: condition.symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(condition.code <= 1 ? skin.sun : skin.ink, rainy ? skin.rain : (condition.code == 2 ? skin.sun : skin.ink))
            .font(.system(size: 15, weight: .semibold))
            .frame(height: 18)
    }
}

private func weekday(_ d: Date, _ tz: TimeZone) -> String {
    let f = DateFormatter(); f.timeZone = tz; f.dateFormat = "EEE"
    return f.string(from: d).uppercased()
}

private extension Color {
    /// Lightens a color toward white by `white` (0…1), for sphere highlights.
    func mix(white amount: Double) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = CGFloat(amount)
        return Color(red: Double(r + (1 - r) * k), green: Double(g + (1 - g) * k), blue: Double(b + (1 - b) * k))
    }
}

// MARK: - Placeholder data

extension Forecast {
    static var sample: Forecast {
        let cal = Calendar.current
        let days = (0..<8).map { i in
            DailyWeather(date: cal.date(byAdding: .day, value: i, to: cal.startOfDay(for: .now))!,
                         high: Double([24, 20, 21, 22, 20, 19, 20, 19][i]), low: Double([14, 16, 15, 15, 16, 13, 14, 14][i]),
                         code: [2, 61, 3, 2, 3, 2, 2, 61][i], precipChance: [5, 45, 20, 10, 20, 15, 15, 45][i],
                         precipSum: 0, sunrise: nil, sunset: nil, uvMax: 5, windMax: 12, gustMax: 20)
        }
        return Forecast(place: .sanDiego,
                        current: CurrentWeather(temperature: 19, apparent: 19, code: 2, isDay: true),
                        daily: days, hourly: [], aqi: nil, timeZone: .current, fetchedAt: .now)
    }
}
