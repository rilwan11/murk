import UIKit
import WidgetKit

/// Renders the widget's 3D sky images: every weather kind × day/night for the current skin.
/// Runs off the main thread, at most once a day per skin (so the moon phase stays right),
/// and draws the picture the widget needs right now before the rest.
enum SceneSnapshotter {
    private static let lock = NSLock()
    private static var busy: Set<String> = []

    static func renderIfNeeded(skin: Skin, first: (ArtKind, Bool)? = nil) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let key = "art.rendered.v\(WidgetArt.version).\(skin.rawValue)"
        let stamp = f.string(from: Date())
        let d = SharedStore.defaults
        guard d.string(forKey: key) != stamp else { return }
        // No App Group (or under test): nowhere to write, nothing to do.
        guard WidgetArt.url(.clear, day: true, skin: skin) != nil, NSClassFromString("XCTestCase") == nil else { return }

        lock.lock()
        let started = busy.insert(key).inserted
        lock.unlock()
        guard started else { return }

        Task.detached(priority: .utility) {
            defer { lock.lock(); busy.remove(key); lock.unlock() }
            let age = Astronomy.moonAge()
            var order: [(ArtKind, Bool)] = []
            if let first { order.append(first) }
            for kind in ArtKind.allCases { for day in [true, false] where !order.contains(where: { $0.0 == kind && $0.1 == day }) { order.append((kind, day)) } }

            var wrote = 0
            for (i, item) in order.enumerated() {
                autoreleasepool {
                    // A fresh scene per picture keeps peak memory low.
                    let scene = WeatherScene()
                    guard let url = WidgetArt.url(item.0, day: item.1, skin: skin),
                          let img = scene.snapshot(cover: item.0.cover, isDay: item.1, moonAge: age, skin: skin,
                                                   size: CGSize(width: 520, height: 520)),
                          let png = img.pngData() else { return }
                    if (try? png.write(to: url, options: .atomic)) != nil { wrote += 1 }
                }
                // The widget can show the current sky as soon as it exists.
                if i == 0, wrote > 0 { WidgetCenter.shared.reloadAllTimelines() }
            }
            if wrote == order.count { d.set(stamp, forKey: key) }
            if wrote > 1 { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}
