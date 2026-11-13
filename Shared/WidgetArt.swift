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
    static let version = 3

    static func url(_ kind: ArtKind, day: Bool, skin: Skin) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedStore.appGroup)?
            .appendingPathComponent("art-v\(version)-\(kind.rawValue)-\(day ? "day" : "night")-\(skin.rawValue).png")
    }

    static func image(_ kind: ArtKind, day: Bool, skin: Skin) -> UIImage? {
        guard let u = url(kind, day: day, skin: skin) else { return nil }
        return UIImage(contentsOfFile: u.path)
    }
}
