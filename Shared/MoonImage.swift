import UIKit

/// A still picture of the moon for a given age: real maria and craters, the terminator in the right
/// place, and faint earthshine on the dark side. Used for small moons (forecast row, widgets).
enum MoonImage {
    private static let cache = NSCache<NSString, UIImage>()

    /// - Parameters: age in days, side in points, the skin's moon tint.
    static func image(age: Double, points: CGFloat, tint: UInt32 = 0xFFFFFF, scale: CGFloat = 3) -> UIImage {
        let px = max(8, Int(points * scale))
        let key = "\(Int((age * 4).rounded()))-\(px)-\(tint)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let th = 2 * Double.pi * age / Astronomy.synodicMonth
        let L = (x: sin(th), y: -0.12 * abs(sin(th)), z: -cos(th))
        let tr = Float((tint >> 16) & 0xFF) / 255, tg = Float((tint >> 8) & 0xFF) / 255, tb = Float(tint & 0xFF) / 255
        var buf = [UInt8](repeating: 0, count: px * px * 4)
        let R = Double(px) / 2
        for j in 0..<px {
            for i in 0..<px {
                let x = (Double(i) + 0.5 - R) / R, y = (R - Double(j) - 0.5) / R
                let rr = x * x + y * y
                let edge = min(1, max(0, (1 - rr.squareRoot()) * R))      // antialiased rim
                guard edge > 0 else { continue }
                let z = max(0, 1 - rr).squareRoot()
                let lon = atan2(x, z), lat = asin(max(-1, min(1, y)))
                let alb = MoonSurface.sample(lon: lon, lat: lat)
                let (sx, sy) = MoonSurface.slope(lon: lon, lat: lat)
                // bumped normal
                var nx = x - Double(sx) * 2.2, ny = y - Double(sy) * 2.2, nz = z
                let nl = (nx * nx + ny * ny + nz * nz).squareRoot(); nx /= nl; ny /= nl; nz /= nl
                let d = nx * L.x + ny * L.y + nz * L.z
                let t = min(1, max(0, (d + 0.03) / 0.12)); let lit = t * t * (3 - 2 * t)
                let shade = 0.5 + 0.5 * max(0, d).squareRoot()
                let k = Float(lit * shade * 1.12)
                let a = Float(edge)
                let r = (alb * tr * k + alb * 0.035) * a, g = (alb * tg * k + alb * 0.042) * a, b = (alb * tb * k + alb * 0.06) * a
                let o = (j * px + i) * 4
                buf[o] = UInt8(min(255, r * 255)); buf[o + 1] = UInt8(min(255, g * 255))
                buf[o + 2] = UInt8(min(255, b * 255)); buf[o + 3] = UInt8(a * 255)
            }
        }
        let cg = CGImage(width: px, height: px, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: CGDataProvider(data: Data(buf) as CFData)!, decode: nil,
                         shouldInterpolate: true, intent: .defaultIntent)!
        let img = UIImage(cgImage: cg, scale: scale, orientation: .up)
        cache.setObject(img, forKey: key)
        return img
    }
}
