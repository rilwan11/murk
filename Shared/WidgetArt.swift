import UIKit

/// Pre-rendered 3D sky images the app writes into the App Group for the widget.
enum ArtKind: String, CaseIterable {
    case clear, partly, cloudy, rain, snow

    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partly
        case 51...67, 80...82, 95...99: self = .rain
        case 71...77, 85, 86: self = .snow
        default: self = .cloudy
        }
    }

    var cover: Double {
        switch self {
        case .clear: return 0.3
        case .partly: return 0.45
        case .cloudy: return 0.8
        case .rain: return 1.0
        case .snow: return 0.85
        }
    }
}

enum WidgetArt {
    /// v4: the moon shows its real phase, and daytime clouds are sunlit white.
    static let version = 4

    static func url(_ kind: ArtKind, day: Bool, skin: Skin, version v: Int = version) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("art-v\(v)-\(kind.rawValue)-\(day ? "day" : "night")-\(skin.rawValue).png")
    }

    /// `legacy` reads the previous version's images until the app has rendered new ones.
    static func image(_ kind: ArtKind, day: Bool, skin: Skin, legacy: Bool = false) -> UIImage? {
        guard let u = url(kind, day: day, skin: skin, version: legacy ? version - 1 : version) else { return nil }
        return UIImage(contentsOfFile: u.path)
    }
}
