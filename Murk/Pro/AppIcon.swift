import UIKit

/// The Home Screen icons. The original is free; the tinted ones are part of Murk Pro.
enum AppIcon: String, CaseIterable, Identifiable {
    case night, aurora, storm, sunset
    var id: String { rawValue }

    var name: String {
        switch self {
        case .night: return String(localized: "Night Murk")
        case .aurora: return String(localized: "Aurora")
        case .storm: return String(localized: "Storm")
        case .sunset: return String(localized: "Sunset")
        }
    }

    var isPremium: Bool { self != .night }
    /// The alternate icon set's name; nil is the icon the app ships with.
    var alternateName: String? { self == .night ? nil : "AppIcon-\(rawValue.capitalized)" }
    var previewImage: String { self == .night ? "IconPreview-Default" : "IconPreview-\(rawValue.capitalized)" }

    static func named(_ alternate: String?) -> AppIcon {
        allCases.first { $0.alternateName == alternate } ?? .night
    }

    @MainActor static var current: AppIcon { named(UIApplication.shared.alternateIconName) }

    @MainActor static func set(_ icon: AppIcon) async -> Bool {
        guard UIApplication.shared.supportsAlternateIcons else { return false }
        guard icon != current else { return true }
        do { try await UIApplication.shared.setAlternateIconName(icon.alternateName); return true } catch { return false }
    }

    /// When Murk Pro ends, the icon goes back to the original.
    @MainActor static func revertIfPremium() {
        guard current.isPremium else { return }
        Task { _ = await set(.night) }
    }
}
