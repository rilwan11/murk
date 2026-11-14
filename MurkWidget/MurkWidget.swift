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
            let first = await load()
            // Same forecast, but the sky behind it keeps moving through the next hour.
            let entries = (0..<4).map { i in
                WeatherEntry(date: first.date.addingTimeInterval(Double(i) * 15 * 60), forecast: first.forecast, unit: first.unit, skin: first.skin)
            }
            // Refresh every 30 minutes (iOS may stretch this to save battery).
            completion(Timeline(entries: entries, policy: .after(Date().addingTimeInterval(30 * 60))))
        }
    }

    /// Draws from the snapshot the app shares. The network is used only when there's no usable
    /// snapshot, and then just once, briefly.
    private func load() async -> WeatherEntry {
        let saved = WidgetSnapshot.load()
        if let s = saved, s.isFresh() { return entry(s) }

        var repo = WeatherRepository()
        repo.firstTimeout = 8
        repo.allowRetry = false
        if let f = try? await repo.core(for: SharedStore.place) {
            let s = WidgetSnapshot(forecast: f, unit: saved?.tempUnit ?? SharedStore.unit, skin: saved?.skinValue ?? SharedStore.skin)
            s.save()
            return entry(s)
        }
        if let s = saved, s.isUsable() { return entry(s) }     // offline: the last forecast still beats nothing
        return WeatherEntry(date: .now, forecast: nil, unit: SharedStore.unit, skin: SharedStore.skin)
    }

    private func entry(_ s: WidgetSnapshot) -> WeatherEntry {
        WeatherEntry(date: .now, forecast: s.forecast, unit: s.tempUnit, skin: s.skinValue)
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
        .description("Weather with Atmosphere.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    let entry: WeatherEntry

    private var isHome: Bool { [.systemSmall, .systemMedium, .systemLarge].contains(family) }

    /// The whole widget in one sentence for VoiceOver.
    private var spoken: String {
        guard let f = entry.forecast else { return String(localized: "Murk. Open the app to load the forecast.") }
        let u = entry.unit
        var s = String(localized: "\(f.place.name), \(u.temp(f.current.temperature)) degrees, \(f.current.condition.title)")
        if let d = f.daily.first { s += String(localized: ". High \(u.temp(d.high)), low \(u.temp(d.low)), \(d.precipChance) percent chance of rain") }
        if f.isStale() { s += String(localized: ". Updated \(f.fetchedAt.formatted(date: .omitted, time: .shortened))") }
        return s
    }

    var body: some View {
        // The same live sky as the app (dawn, blue day, golden hour, dusk, navy night, grey under cloud).
        // On tinted/clear home screens iOS turns all text one color, so the sky goes deeper to keep it readable,
        // and it's drawn as a picture, which is the one thing iOS lets keep its color there.
        let accented = mode != .fullColor
        let live = entry.forecast.flatMap { Sky.current($0, skin: entry.skin, at: entry.date) }
        let sky = accented ? (live ?? Sky.at(altitude: -30, cover: 0, precip: false)).deepened() : live
        let p = Palette(skin: entry.skin, sky: sky)
        Group {
            if let f = entry.forecast {
                switch family {
                case .systemSmall: SmallView(f: f, u: entry.unit, skin: entry.skin)
                case .systemMedium: MediumView(f: f, u: entry.unit, skin: entry.skin)
                case .systemLarge: LargeView(f: f, u: entry.unit, skin: entry.skin, date: entry.date)
                case .accessoryCircular: CircularView(f: f, u: entry.unit)
                case .accessoryRectangular: RectangularView(f: f, u: entry.unit)
                case .accessoryInline: Text("\(entry.unit.temp(f.current.temperature))° \(f.current.condition.title)")
                default: SmallView(f: f, u: entry.unit, skin: entry.skin)
                }
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "icloud.slash")
                    Text("Open Murk to load the forecast").font(.caption2).multilineTextAlignment(.center)
                }
                .foregroundStyle(p.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
        .background {
            if accented, isHome, let sky { fullColorImage(sky.image()).padding(-60) }
        }
        .environment(\.widgetPalette, p)
        .environment(\.widgetSky, sky)
        .containerBackground(for: .widget) {
            if let sky { SkyBackground(sky: sky) } else { entry.skin.bg }
        }
        .widgetURL(URL(string: "murk://now"))
    }
}

// MARK: - Colors

private struct PaletteKey: EnvironmentKey { static let defaultValue: Palette? = nil }
private struct WidgetSkyKey: EnvironmentKey { static let defaultValue: Sky? = nil }
extension EnvironmentValues {
    /// Text colors that read on whatever the widget is showing behind them.
    var widgetPalette: Palette? { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } }
    var widgetSky: Sky? { get { self[WidgetSkyKey.self] } set { self[WidgetSkyKey.self] = newValue } }
}

// MARK: - Home screen sizes

private extension Font {
    static func bigTemp(_ size: CGFloat) -> Font { .system(size: size, weight: .black).width(.compressed) }
}

/// The temperature as a sculpted, extruded slab — stacked offset layers for depth,
/// a lit gradient face and a faint highlight edge, like the 3D digits in the app.
struct ExtrudedText: View {
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.widgetSky) private var sky
    let text: String
    let size: CGFloat
    let skin: Skin

    var body: some View {
        if mode == .fullColor { sculpted(face: nil) } else if let img = rendered() {
            // Tinted / clear home screens recolor every layer the same, so the sculpted digits go in as a
            // picture: pale, lit stone on the deep sky behind.
            fullColorImage(img).scaledToFit().frame(maxHeight: size * 1.1)
        } else {
            Text(text).font(.bigTemp(size)).widgetAccentable()
                .lineLimit(1).minimumScaleFactor(0.5)
        }
    }

    @MainActor private func rendered() -> UIImage? {
        let r = ImageRenderer(content: sculpted(face: Color(hex: 0xDCE4EE)).padding(size * 0.04))
        r.scale = 3
        return r.uiImage
    }

    @ViewBuilder private func sculpted(face override: Color?) -> some View {
        let f = Font.bigTemp(size)
        // On a sunny sky the digits go slate, like the app's daytime look.
        let face = override ?? ((sky?.bright == true) ? Color(hex: 0x2B3F5C) : Color(hex: skin.digitHex))
        let shadow = (sky?.bright == true) ? 0.25 : 0.55
        let depth = 9
        ZStack {
            ForEach(0..<depth, id: \.self) { i in
                let k = CGFloat(depth - i)
                Text(text).font(f)
                    .foregroundStyle(Color.black.opacity(shadow + 0.04 * Double(i)))
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
    @Environment(\.widgetSky) private var sky
    let code: Int
    let isDay: Bool
    let skin: Skin

    var body: some View {
        let kind = ArtKind(code: code)
        ZStack {
            if let ui = WidgetArt.image(kind, day: isDay, skin: skin) ?? WidgetArt.image(kind, day: isDay, skin: skin, legacy: true) {
                skyImage(ui)
            } else {
                CloudArt(cover: kind.cover, isDay: isDay, skin: skin, sunny: sky?.bright == true).padding(10)
            }
            if kind == .rain || kind == .snow {
                Canvas { ctx, size in
                    var rng = RainRandom(seed: 7)
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

/// A picture that keeps its own colors on tinted and clear home screens.
@ViewBuilder
func fullColorImage(_ ui: UIImage) -> some View {
    if #available(iOS 18.0, *) {
        Image(uiImage: ui).resizable().widgetAccentedRenderingMode(.fullColor)
    } else {
        Image(uiImage: ui).resizable()
    }
}

@ViewBuilder
private func skyImage(_ ui: UIImage) -> some View {
    // Fill the width (the clouds sit in the middle band of the square render) so they read larger.
    if #available(iOS 18.0, *) {
        Image(uiImage: ui).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
    } else {
        Image(uiImage: ui).resizable().scaledToFill()
    }
}

struct RainRandom {
    private var s: UInt64
    init(seed: UInt64) { s = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

/// Cloud above, sculpted temperature tucked underneath — the app's main screen in miniature.
struct HeroStack: View {
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, u: TempUnit, skin: Skin
    var skySize: CGFloat
    var tempSize: CGFloat
    var skyRatio: CGFloat = 0.62
    var showHiLo = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: -tempSize * 0.42) {
                Sky3D(code: f.current.code, isDay: f.current.isDay, skin: skin)
                    .frame(width: skySize, height: skySize * skyRatio)
                    .clipped()
                    .zIndex(1)
                ExtrudedText(text: "\(u.temp(f.current.temperature))", size: tempSize, skin: skin)
            }
            if showHiLo, let d = f.daily.first {
                Text("H \(u.temp(d.high))°  L \(u.temp(d.low))°")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pal?.muted ?? skin.muted)
                    .widgetAccentable()
            }
        }
    }
}

struct SmallView: View {
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, u: TempUnit, skin: Skin
    var showHiLo = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                if f.place.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: 8, weight: .bold)) }
                Text(f.place.name).font(.system(size: 12, weight: .heavy)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(pal?.ink ?? skin.ink)
            .widgetAccentable()
            HeroStack(f: f, u: u, skin: skin, skySize: 152, tempSize: showHiLo ? 72 : 86,
                      skyRatio: showHiLo ? 0.56 : 0.62, showHiLo: showHiLo)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct MediumView: View {
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        let ink = pal?.ink ?? skin.ink, muted = pal?.muted ?? skin.muted
        HStack(spacing: 10) {
            SmallView(f: f, u: u, skin: skin, showHiLo: true).frame(width: 152)
            VStack(alignment: .leading, spacing: 6) {
                Text(f.current.condition.title).font(.system(size: 15, weight: .black)).lineLimit(1)
                    .foregroundStyle(ink)
                HStack(spacing: 0) {
                    ForEach(Array(f.daily.dropFirst().prefix(5).enumerated()), id: \.offset) { _, d in
                        VStack(spacing: 4) {
                            Text(weekday(d.date, f.timeZone)).font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                            WidgetDayIcon(condition: d.condition, skin: skin)
                            Text("\(u.temp(d.high))").font(.system(size: 14, weight: .heavy))
                            Text("\(u.temp(d.low))").font(.system(size: 14, weight: .heavy)).foregroundStyle(muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .foregroundStyle(ink)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14).fill(pal?.glass ?? .clear))
            }
        }
    }
}

struct LargeView: View {
    @Environment(\.widgetPalette) private var pal
    let f: Forecast, u: TempUnit, skin: Skin
    var date: Date = .now
    var body: some View {
        let ink = pal?.ink ?? skin.ink, muted = pal?.muted ?? skin.muted, line = pal?.line ?? skin.line
        let days = Array(f.daily.prefix(5))
        let lo = days.map(\.low).min() ?? 0, hi = days.map(\.high).max() ?? 1
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                if f.place.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: 10, weight: .bold)) }
                Text(f.place.name).font(.system(size: 16, weight: .heavy)).lineLimit(1)
            }
            .foregroundStyle(ink)
            HeroStack(f: f, u: u, skin: skin, skySize: 280, tempSize: 118, skyRatio: 0.5)
                .frame(height: 165)
            Text(f.current.condition.title).font(.system(size: 18, weight: .black)).foregroundStyle(ink)
            Spacer(minLength: 0)
            VStack(spacing: 3) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                HStack(spacing: 10) {
                    Text(i == 0 ? "TODAY" : weekday(d.date, f.timeZone))
                        .font(.system(size: 11, design: .monospaced)).frame(width: 44, alignment: .leading)
                    WidgetDayIcon(condition: d.condition, skin: skin).frame(width: 24)
                    Text("\(u.temp(d.low))").font(.system(size: 13, weight: .heavy)).foregroundStyle(muted).frame(width: 26, alignment: .trailing)
                    GeometryReader { g in
                        let x0 = (d.low - lo) / max(hi - lo, 1), x1 = (d.high - lo) / max(hi - lo, 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(line).frame(height: 5)
                            Capsule().fill(LinearGradient(colors: [Color(hex: 0x7CC4FF), Color(hex: 0xFFC14D), Color(hex: 0xFF6B3D)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(6, g.size.width * (x1 - x0)), height: 5)
                                .offset(x: g.size.width * x0)
                        }
                        .frame(maxHeight: .infinity)
                    }
                    Text("\(u.temp(d.high))").font(.system(size: 13, weight: .heavy)).frame(width: 26, alignment: .trailing)
                }
                .foregroundStyle(ink)
                .frame(height: 19)
            }
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 16).fill(pal?.glass ?? .clear))
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
    var sunny = false

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
                        .fill(RadialGradient(colors: sunny ? [.white, Color(hex: 0xE4E9F0), Color(hex: 0x9FB0C8)]
                                                           : [Color(hex: skin.cloudHex).opacity(1).mix(white: 0.28), Color(hex: skin.cloudHex), .black],
                                             center: UnitPoint(x: 0.34, y: 0.26), startRadius: 0, endRadius: w * p.2 * 1.6))
                        .frame(width: w * p.2 * 2, height: w * p.2 * 2)
                        .position(x: w * p.0, y: h * p.1)
                }
            }
        }
    }

    @ViewBuilder private var orb: some View {
        if isDay {
            Circle().fill(RadialGradient(colors: [.white, Color(hex: 0xFFE27A), Color(hex: 0xFFB43A)], center: UnitPoint(x: 0.42, y: 0.4), startRadius: 0, endRadius: 40))
                .shadow(color: Color(hex: 0xFFC14D).opacity(0.7), radius: 12)
        } else {
            Image(uiImage: MoonImage.image(age: Astronomy.moonAge(), points: 80, tint: skin.moonHex)).resizable()
        }
    }
}

struct WidgetDayIcon: View {
    @Environment(\.widgetPalette) private var pal
    let condition: Condition
    let skin: Skin
    var body: some View {
        let rainy = condition.precip == .rain
        let ink = pal?.ink ?? skin.ink
        Image(systemName: condition.symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(condition.code <= 1 ? Color(hex: 0xFFB43A) : ink, rainy ? skin.rain : (condition.code == 2 ? Color(hex: 0xFFB43A) : ink))
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
