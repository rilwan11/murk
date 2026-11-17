import WidgetKit
import SwiftUI

// The Murk widget in its smoked-glass design: one surface, the floating-sphere art behind a tall
// flat temperature, the other unit and the day's high and low beneath, and five filled forecast icons.

enum MurkGlass {
    static let top = Color(hex: 0x24385A)
    static let bottom = Color(hex: 0x111C31)
    static let ink = Color.white
    /// Lows and secondary lines.
    static let muted = Color(hex: 0xA3B3CC)
    static let gold = Color(hex: 0xFFC247)
    static let amber = Color(hex: 0xFF9E2C)
    static let pearl = Color(hex: 0xF3F5F9)
    static let rainCloud = Color(hex: 0xAFC4E0)
    static let cyan = Color(hex: 0x3FE0F0)
}

/// Dark navy smoked glass, used on full-color home screens (Clear and Tinted get the system's own glass).
struct GlassSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [MurkGlass.top, MurkGlass.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            // A soft sheen across the top edge, like light on glass.
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
        }
    }
}

/// The colors a layout draws with: the glass palette, or the chosen style's when that isn't the glass.
struct GlassInk {
    let ink: Color, muted: Color
    static let glass = GlassInk(ink: MurkGlass.ink, muted: MurkGlass.muted)
}

private struct GlassInkKey: EnvironmentKey { static let defaultValue = GlassInk.glass }
extension EnvironmentValues {
    var glassInk: GlassInk { get { self[GlassInkKey.self] } set { self[GlassInkKey.self] = newValue } }
}

/// Both readings from the same unrounded value, each rounded on its own.
struct Readings {
    let main: String, other: String, hiLo: String
    let spokenMain: String, spokenOther: String

    init(_ f: Forecast, _ u: TempUnit) {
        let c = f.current.temperature
        let o: TempUnit = u == .fahrenheit ? .celsius : .fahrenheit
        main = "\(u.temp(c))"
        other = "\(o.temp(c))\(o.symbol)"
        hiLo = f.daily.first.map { "H \(u.temp($0.high))°  L \(u.temp($0.low))°" } ?? ""
        let name: (TempUnit) -> String = { $0 == .fahrenheit ? String(localized: "Fahrenheit") : String(localized: "Celsius") }
        spokenMain = String(localized: "\(u.temp(c)) degrees \(name(u))")
        spokenOther = String(localized: "\(o.temp(c)) degrees \(name(o))")
    }

    /// "19°C · H 69° L 58°"
    var footer: String { hiLo.isEmpty ? other : "\(other)  ·  \(hiLo)" }
}

/// The floating spheres with the temperature in front; a soft amber halo behind the sun when it's out.
struct GlassHero: View {
    @Environment(\.glassInk) private var ink
    let f: Forecast, u: TempUnit, skin: Skin

    var body: some View {
        GeometryReader { g in
            let h = g.size.height, w = g.size.width
            let artSide = min(w, h * 1.25)
            let sunny = f.current.isDay && f.current.code <= 2
            ZStack {
                if sunny {
                    RadialGradient(colors: [MurkGlass.amber.opacity(0.45), MurkGlass.amber.opacity(0.12), .clear],
                                   center: UnitPoint(x: 0.64, y: 0.3), startRadius: 0, endRadius: artSide * 0.42)
                        .frame(width: w, height: h)
                        .allowsHitTesting(false)
                }
                Sky3D(code: f.current.code, isDay: f.current.isDay, skin: skin)
                    .frame(width: artSide, height: artSide * 0.8)
                    .position(x: w / 2, y: h * 0.38)
                Text(Readings(f, u).main)
                    .font(.system(size: h * 0.6, weight: .bold).width(.compressed))
                    .foregroundStyle(ink.ink)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .widgetAccentable()
                    .position(x: w / 2, y: h * 0.66)
            }
        }
    }
}

struct GlassCity: View {
    @Environment(\.glassInk) private var ink
    let f: Forecast
    var size: CGFloat = 15
    var body: some View {
        HStack(spacing: 4) {
            if f.place.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: size * 0.6, weight: .bold)) }
            Text(f.place.name).font(.system(size: size, weight: .bold)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(ink.ink)
        .widgetAccentable()
    }
}

struct GlassFooter: View {
    @Environment(\.glassInk) private var ink
    let text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .medium).monospacedDigit())
            .foregroundStyle(ink.ink.opacity(0.92))
            .lineLimit(1).minimumScaleFactor(0.7)
    }
}

/// The left-hand block shared by Small and Medium: city, art and temperature, then the footer.
struct GlassCurrent: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GlassCity(f: f)
            GlassHero(f: f, u: u, skin: skin).frame(maxWidth: .infinity, maxHeight: .infinity)
            GlassFooter(text: Readings(f, u).footer).frame(maxWidth: .infinity)
        }
    }
}

struct GlassSmall: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View { GlassCurrent(f: f, u: u, skin: skin) }
}

struct GlassMedium: View {
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        HStack(spacing: 8) {
            GlassCurrent(f: f, u: u, skin: skin).frame(width: 150)
            ForecastColumns(f: f, u: u, iconSize: 22, highSize: 17, lowSize: 15)
        }
    }
}

struct GlassLarge: View {
    @Environment(\.glassInk) private var ink
    let f: Forecast, u: TempUnit, skin: Skin
    var body: some View {
        let r = Readings(f, u)
        VStack(alignment: .leading, spacing: 6) {
            GlassCity(f: f, size: 18)
            HStack(alignment: .center, spacing: 10) {
                GlassHero(f: f, u: u, skin: skin).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(f.current.condition.title).font(.system(size: 20, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(r.other).font(.system(size: 17, weight: .medium).monospacedDigit())
                    Text(r.hiLo).font(.system(size: 17, weight: .medium).monospacedDigit())
                }
                .foregroundStyle(ink.ink)
                .widgetAccentable()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            ForecastColumns(f: f, u: u, iconSize: 30, highSize: 21, lowSize: 19)
                .frame(maxHeight: .infinity)
        }
    }
}

/// The next five local days: weekday, icon, high, low, in evenly spaced columns straight on the glass.
struct ForecastColumns: View {
    @Environment(\.glassInk) private var ink
    let f: Forecast, u: TempUnit
    var iconSize: CGFloat, highSize: CGFloat, lowSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(Self.nextDays(f).enumerated()), id: \.offset) { _, d in
                VStack(spacing: 5) {
                    Text(Self.weekday(d.date, f.timeZone))
                        .font(.system(size: highSize * 0.68, weight: .semibold))
                        .foregroundStyle(ink.ink)
                    ForecastIcon(condition: d.condition, size: iconSize)
                    Text("\(u.temp(d.high))°").font(.system(size: highSize, weight: .bold).monospacedDigit())
                        .foregroundStyle(ink.ink)
                    Text("\(u.temp(d.low))°").font(.system(size: lowSize, weight: .semibold).monospacedDigit())
                        .foregroundStyle(ink.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .widgetAccentable()
    }

    /// Tomorrow onward, five local calendar days.
    static func nextDays(_ f: Forecast) -> [DailyWeather] {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = f.timeZone
        let today = cal.startOfDay(for: Date())
        return Array(f.daily.filter { cal.startOfDay(for: $0.date) > today }.prefix(5))
    }

    static func weekday(_ d: Date, _ tz: TimeZone) -> String {
        let fmt = DateFormatter(); fmt.timeZone = tz; fmt.dateFormat = "EEE"
        return fmt.string(from: d).uppercased()
    }
}

/// Filled forecast icons with distinct silhouettes, so they read in grayscale too.
struct ForecastIcon: View {
    @Environment(\.widgetRenderingMode) private var mode
    let condition: Condition
    let size: CGFloat

    var body: some View {
        if mode == .fullColor {
            drawn
        } else if let img = rendered() {
            // Clear and Tinted home screens recolor shapes; a picture keeps the gold and cyan.
            fullColorImage(img).scaledToFit().frame(width: size * 1.35, height: size * 1.25)
        } else {
            drawn
        }
    }

    @MainActor private func rendered() -> UIImage? {
        let r = ImageRenderer(content: drawn.environment(\.widgetRenderingMode, .fullColor))
        r.scale = 3
        return r.uiImage
    }

    private var drawn: some View {
        ZStack {
            switch condition.precip {
            case .rain: rain
            case .snow: snow
            default:
                if condition.code >= 95 { storm }
                else if condition.code <= 1 { sun(size * 0.78) }
                else if condition.code == 2 { partly }
                else { cloud(MurkGlass.pearl) }
            }
        }
        .frame(width: size * 1.35, height: size * 1.25)
        .accessibilityHidden(true)
    }

    private func sun(_ d: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xFFE08A), MurkGlass.gold, MurkGlass.amber], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.7))
            .frame(width: d, height: d)
    }

    private func cloud(_ c: Color) -> some View {
        Image(systemName: "cloud.fill").resizable().scaledToFit()
            .foregroundStyle(c)
            .frame(width: size * 1.3)
    }

    private var partly: some View {
        ZStack {
            sun(size * 0.7).offset(x: size * 0.22, y: -size * 0.22)
            cloud(MurkGlass.pearl).scaleEffect(0.86).offset(x: -size * 0.06, y: size * 0.14)
        }
    }

    private var rain: some View {
        VStack(spacing: size * 0.06) {
            cloud(MurkGlass.rainCloud).frame(height: size * 0.75)
            HStack(spacing: size * 0.16) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(MurkGlass.cyan).frame(width: size * 0.09, height: size * 0.34).rotationEffect(.degrees(18))
                }
            }
        }
    }

    private var snow: some View {
        VStack(spacing: size * 0.08) {
            cloud(MurkGlass.pearl).frame(height: size * 0.75)
            HStack(spacing: size * 0.16) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.white).frame(width: size * 0.14) }
            }
        }
    }

    private var storm: some View {
        Image(systemName: "cloud.bolt.fill").resizable().scaledToFit()
            .symbolRenderingMode(.palette)
            .foregroundStyle(MurkGlass.rainCloud, MurkGlass.gold)
            .frame(width: size * 1.3)
    }
}

/// VoiceOver: the whole reading, then the days in order.
enum GlassSpeech {
    static func line(_ f: Forecast, _ u: TempUnit) -> String {
        let r = Readings(f, u)
        var s = "\(f.place.name), \(f.current.condition.title.lowercased()), \(r.spokenMain), \(r.spokenOther)."
        if let d = f.daily.first { s += " " + String(localized: "High \(u.temp(d.high)), low \(u.temp(d.low)).") }
        for d in ForecastColumns.nextDays(f) {
            let day = d.date.formatted(Date.FormatStyle(timeZone: f.timeZone).weekday(.wide))
            s += " " + String(localized: "\(day): \(d.condition.title.lowercased()), high \(u.temp(d.high)), low \(u.temp(d.low)).")
        }
        if f.isStale() { s += " " + String(localized: "Updated \(f.fetchedAt.formatted(date: .omitted, time: .shortened)).") }
        return s
    }
}
