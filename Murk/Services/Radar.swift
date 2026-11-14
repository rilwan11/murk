import Foundation
import MapKit
import UIKit

/// One radar picture of the past two hours.
struct RadarFrame: Identifiable, Hashable {
    var time: Date
    var path: String
    var id: String { path }
}

/// Radar from RainViewer's public Weather Maps API: the past two hours in 10-minute frames.
/// Its free terms are personal and educational use with visible credit; a commercial release
/// needs RainViewer's commercial terms or another source (see docs/APP_STORE.md).
enum RadarService {
    static let index = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
    static let credit = URL(string: "https://www.rainviewer.com")!
    /// RainViewer's free tiles stop at zoom 7; closer views are cut from those.
    static let maxZoom = 7

    struct Catalog: Equatable {
        var host: String
        var frames: [RadarFrame]
    }

    private struct Payload: Decodable {
        struct Radar: Decodable { var past: [Item] }
        struct Item: Decodable { var time: TimeInterval; var path: String }
        var host: String
        var radar: Radar
    }

    static func parse(_ data: Data) throws -> Catalog {
        let p = try JSONDecoder().decode(Payload.self, from: data)
        let frames = p.radar.past.map { RadarFrame(time: Date(timeIntervalSince1970: $0.time), path: $0.path) }
            .sorted { $0.time < $1.time }
        return Catalog(host: p.host, frames: frames)
    }

    static func catalog() async throws -> Catalog {
        var req = URLRequest(url: index, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("Murk", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try parse(data)
    }

    /// Tile picture address. Color scheme 2 (Universal Blue) is the one the free API keeps; 1_1 = smoothed, with snow.
    static func tileURL(host: String, path: String, z: Int, x: Int, y: Int) -> URL? {
        URL(string: "\(host)\(path)/256/\(z)/\(x)/\(y)/2/1_1.png")
    }

    /// The zoom-7 tile that holds a closer tile, and where inside it (in 0…1 units) the closer tile sits.
    static func source(z: Int, x: Int, y: Int) -> (z: Int, x: Int, y: Int, rect: CGRect) {
        let dz = max(0, z - maxZoom)
        guard dz > 0 else { return (z, x, y, CGRect(x: 0, y: 0, width: 1, height: 1)) }
        let n = 1 << dz
        let px = x >> dz, py = y >> dz
        let side = 1 / CGFloat(n)
        return (z - dz, px, py, CGRect(x: CGFloat(x - px * n) * side, y: CGFloat(y - py * n) * side, width: side, height: side))
    }

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 64 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: c)
    }()
}

/// A radar frame as map tiles, cut from zoom 7 when the map is closer than that.
final class RadarTileOverlay: MKTileOverlay {
    let host: String
    let frame: RadarFrame

    init(host: String, frame: RadarFrame) {
        self.host = host
        self.frame = frame
        super.init(urlTemplate: nil)
        canReplaceMapContent = false
        tileSize = CGSize(width: 256, height: 256)
        minimumZ = 1
        maximumZ = 12
    }

    override func loadTile(at p: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let s = RadarService.source(z: p.z, x: p.x, y: p.y)
        guard let url = RadarService.tileURL(host: host, path: frame.path, z: s.z, x: s.x, y: s.y) else { result(nil, nil); return }
        RadarService.session.dataTask(with: url) { data, _, error in
            guard let data, s.z != p.z else { result(data, error); return }
            result(Self.cut(data, s.rect), nil)
        }.resume()
    }

    /// Enlarges part of a tile to a whole tile.
    static func cut(_ data: Data, _ rect: CGRect) -> Data? {
        guard let cg = UIImage(data: data)?.cgImage else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let crop = CGRect(x: rect.minX * w, y: rect.minY * h, width: rect.width * w, height: rect.height * h).integral
        guard let part = cg.cropping(to: crop) else { return nil }
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        let out = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .medium
            UIImage(cgImage: part).draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
        }
        return out.pngData()
    }
}
