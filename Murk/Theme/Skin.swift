import SwiftUI
import UIKit

enum Skin: String, CaseIterable, Identifiable {
    case graphite, ember, aurora
    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    // Hex palettes, shared by SwiftUI and SceneKit.
    var bgHex: UInt32 { pick(0x1D1D1D, 0xF0A23A, 0x0C0B1A) }
    var inkHex: UInt32 { pick(0xFFFFFF, 0x1A1206, 0xFFFFFF) }
    var mutedHex: UInt32 { pick(0x7A7A7A, 0x7A4D10, 0x8C86B8) }
    var lineHex: UInt32 { pick(0x333333, 0xB57422, 0x2E2A52) }
    var cloudHex: UInt32 { pick(0x2E2E2E, 0x4A2C0A, 0x4B3AA8) }
    var digitHex: UInt32 { pick(0x2A2A2A, 0x3E2508, 0x3D31A0) }
    var moonHex: UInt32 { pick(0xE9ECEC, 0xFFF2D6, 0xB9F3FF) }
    var sunHex: UInt32 { pick(0xE5393A, 0xFFFFFF, 0xFF7AE0) }
    var accentHex: UInt32 { 0xF2B33D }

    private func pick(_ g: UInt32, _ e: UInt32, _ a: UInt32) -> UInt32 {
        switch self {
        case .graphite: return g
        case .ember: return e
        case .aurora: return a
        }
    }
    var rainHex: UInt32 { 0x3EA0FF }

    var bg: Color { Color(hex: bgHex) }
    var ink: Color { Color(hex: inkHex) }
    var muted: Color { Color(hex: mutedHex) }
    var line: Color { Color(hex: lineHex) }
    var sun: Color { Color(hex: sunHex) }
    var moon: Color { Color(hex: moonHex) }
    var cloud: Color { Color(hex: cloudHex) }
    var accent: Color { Color(hex: accentHex) }
    var rain: Color { Color(hex: rainHex) }

    /// Preview swatch for the skin picker.
    var swatch: AnyShapeStyle {
        switch self {
        case .graphite: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3A3A3A), Color(hex: 0x1E1E1E)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ember: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xF5B445), Color(hex: 0xEC9A33)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .aurora: return AnyShapeStyle(Color(hex: 0x08071A))
        }
    }
    var gem: AnyShapeStyle {
        switch self {
        case .graphite: return AnyShapeStyle(RadialGradient(colors: [Color(hex: 0x666666), Color(hex: 0x1A1A1A)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60))
        case .ember: return AnyShapeStyle(RadialGradient(colors: [Color(hex: 0x6A4310), Color(hex: 0x120A02)], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60))
        case .aurora: return AnyShapeStyle(LinearGradient(colors: [Color(hex: 0xFF9BF0), Color(hex: 0x4B6BFF), Color(hex: 0x9EFFFF)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
    var swatchText: Color { self == .ember ? Color(hex: 0x1A1206) : (self == .aurora ? Color(hex: 0xC9B8FF) : .white) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Type

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .black) }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
}
