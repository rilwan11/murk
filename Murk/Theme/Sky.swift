import SwiftUI

/// The sky behind the 3D scene: it follows the sun through the day
/// (dawn pinks, blue midday, golden afternoon, dusk violet, navy night) and greys out under cloud.
/// It also picks text colors that stay readable on top of it.
struct Sky: Equatable {
    var top: UInt32, mid: UInt32, bottom: UInt32
    var glow: UInt32, glowOpacity: Double
    /// Bright skies get dark navy text; darker skies keep white.
    var bright: Bool

    var ink: Color { bright ? Color(hex: 0x13233D) : .white }
    var muted: Color { bright ? Color(hex: 0x3B4C66) : Color.white.opacity(0.68) }
    var line: Color { bright ? Color(hex: 0x13233D).opacity(0.18) : Color.white.opacity(0.22) }
    /// Frosted card behind the forecast so it reads over haze.
    var glass: Color { bright ? Color.white.opacity(0.5) : Color.black.opacity(0.2) }

    private typealias Key = (alt: Double, top: UInt32, mid: UInt32, bottom: UInt32, glow: UInt32, glowOp: Double)
    private static let clear: [Key] = [
        (-90, 0x070D22, 0x0E1A3C, 0x2B3460, 0x4A4E7A, 0.55),   // night
        (-6,  0x0A1430, 0x16244E, 0x3A3A6E, 0x6A527E, 0.55),   // late twilight
        (-1,  0x26315E, 0xA45E7E, 0xF0955A, 0xFFB070, 0.65),   // sunrise / sunset
        (6,   0x3D69B2, 0x9AB2DA, 0xF6C48A, 0xFFD9A0, 0.55),   // golden hour
        (18,  0x4A8FDE, 0x8CBCEB, 0xEDDCC0, 0xFFF0D0, 0.35),   // morning / afternoon
        (45,  0x3F86DA, 0x84B8EC, 0xDCE3E8, 0xFFFFFF, 0.25),   // midday
        (90,  0x3F86DA, 0x84B8EC, 0xDCE3E8, 0xFFFFFF, 0.25),
    ]
    private static let grey: [Key] = [
        (-90, 0x101319, 0x181C24, 0x262B35, 0x3A3F4A, 0.35),
        (-6,  0x141821, 0x1F242E, 0x323844, 0x4A4F5C, 0.35),
        (-1,  0x2A303E, 0x4F5566, 0x7C7480, 0x9A8A8C, 0.4),
        (6,   0x46536A, 0x6A7690, 0x8E95A6, 0xB0B4BE, 0.3),
        (18,  0x55657E, 0x75849C, 0x98A2B2, 0xC0C6CF, 0.25),
        (90,  0x55657E, 0x75849C, 0x98A2B2, 0xC0C6CF, 0.25),
    ]

    /// - Parameters: altitude of the sun in degrees, cloud cover 0...1, whether it's raining/snowing.
    static func at(altitude: Double, cover: Double, precip: Bool) -> Sky {
        let g = precip ? 1 : min(1, max(0, (cover - 0.5) / 0.4))
        let a = sample(clear, altitude), b = sample(grey, altitude)
        func mix(_ x: UInt32, _ y: UInt32) -> UInt32 { lerp(x, y, g) }
        let top = mix(a.top, b.top), mid = mix(a.mid, b.mid), bottom = mix(a.bottom, b.bottom)
        return Sky(top: top, mid: mid, bottom: bottom,
                   glow: mix(a.glow, b.glow), glowOpacity: a.glowOp + (b.glowOp - a.glowOp) * g,
                   bright: altitude >= 3 && g < 0.6)
    }

    private static func sample(_ keys: [Key], _ alt: Double) -> Key {
        guard let i = keys.lastIndex(where: { $0.alt <= alt }) else { return keys[0] }
        guard i + 1 < keys.count else { return keys[i] }
        let a = keys[i], b = keys[i + 1]
        let t = (alt - a.alt) / (b.alt - a.alt)
        return (alt, lerp(a.top, b.top, t), lerp(a.mid, b.mid, t), lerp(a.bottom, b.bottom, t),
                lerp(a.glow, b.glow, t), a.glowOp + (b.glowOp - a.glowOp) * t)
    }

    static func lerp(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) + (ch(b, s) - ch(a, s)) * t).rounded()) << s }
        return m(16) | m(8) | m(0)
    }
}

struct SkyBackground: View {
    let sky: Sky
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(hex: sky.top), location: 0),
                .init(color: Color(hex: sky.mid), location: 0.5),
                .init(color: Color(hex: sky.bottom), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: sky.glow).opacity(sky.glowOpacity), .clear],
                           center: .bottom, startRadius: 0, endRadius: 440)
        }
        .ignoresSafeArea()
    }
}

/// Text colors for views drawn on top of the sky (nil = use the skin's own colors).
private struct SkyKey: EnvironmentKey { static let defaultValue: Sky? = nil }
extension EnvironmentValues {
    var sky: Sky? {
        get { self[SkyKey.self] }
        set { self[SkyKey.self] = newValue }
    }
}

extension Sky {
    /// The sky over a place right now (nil on the light skins, which keep their flat color).
    static func current(_ f: Forecast, skin: Skin, at date: Date = Date()) -> Sky? {
        guard !skin.isLight else { return nil }
        let alt = Astronomy.sunAltitude(latitude: f.place.latitude, longitude: f.place.longitude, at: date)
        let day = f.current.isDay || alt > -2
        let c = f.current.condition
        return Sky.at(altitude: day ? alt : min(alt, -12), cover: c.cloudCover, precip: c.precip != .none)
    }
}

/// Text and surface colors for whatever is underneath: the live sky, or the skin's flat color.
struct Palette {
    let ink: Color, muted: Color, line: Color
    /// Frosted card fill.
    let glass: Color
    /// Text drawn on an `ink`-filled pill.
    let onInk: Color
    let bright: Bool

    init(skin: Skin, sky: Sky?) {
        if let sky {
            ink = sky.ink; muted = sky.muted; line = sky.line; glass = sky.glass
            onInk = sky.bright ? .white : Color(hex: 0x13233D); bright = sky.bright
        } else {
            ink = skin.ink; muted = skin.muted; line = skin.line
            glass = skin.isLight ? Color.white.opacity(0.35) : Color.white.opacity(0.06)
            onInk = skin.bg; bright = skin.isLight
        }
    }
}
