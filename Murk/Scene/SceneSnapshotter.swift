import UIKit
import WidgetKit

/// Renders the widget's 3D sky images: every weather kind × day/night for the current skin.
/// Re-renders once a day (so the moon phase stays right) or when the skin changes.
enum SceneSnapshotter {
    @MainActor
    static func renderIfNeeded(skin: Skin) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let key = "art.rendered.v\(WidgetArt.version).\(skin.rawValue)"
        let stamp = f.string(from: Date())
        let d = SharedStore.defaults
        guard d.string(forKey: key) != stamp else { return }

        let scene = WeatherScene()
        let age = Astronomy.moonAge()
        var wrote = 0
        for kind in ArtKind.allCases {
            for day in [true, false] {
                guard let url = WidgetArt.url(kind, day: day, skin: skin),
                      let img = scene.snapshot(cover: kind.cover, isDay: day, moonAge: age, skin: skin,
                                               size: CGSize(width: 520, height: 520)),
                      let png = img.pngData() else { continue }
                if (try? png.write(to: url, options: .atomic)) != nil { wrote += 1 }
            }
        }
        if wrote > 0 {
            d.set(stamp, forKey: key)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
