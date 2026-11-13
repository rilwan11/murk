import UIKit

/// A procedurally generated lunar surface: dark maria, scattered craters with bright rims and
/// shadowed floors, plus a matching normal map so the craters catch the light at the terminator.
enum MoonSurface {
    private static let w = 512, h = 256

    /// Height field 0...1 (equirectangular), built once.
    private static let height: [Float] = {
        var rng = SeededRandom(seed: 7)
        var hgt = [Float](repeating: 0.5, count: w * h)
        func add(cx: Double, cy: Double, r: Double, depth: Float, rim: Float) {
            let rx = Int(r * 1.6) + 2
            for dy in -rx...rx {
                let y = Int(cy) + dy
                guard y >= 0, y < h else { continue }
                // Stretch horizontally near the poles so craters stay round on the sphere.
                let lat = (Double(y) / Double(h) - 0.5) * .pi
                let stretch = 1 / max(cos(lat), 0.25)
                let rxs = Int(Double(rx) * stretch)
                for dx in -rxs...rxs {
                    let x = ((Int(cx) + dx) % w + w) % w
                    let d = (Double(dx) / stretch * Double(dx) / stretch + Double(dy * dy)).squareRoot() / r
                    var v: Float = 0
                    if d < 1 { v = -depth * Float(1 - d * d) }                       // bowl
                    else if d < 1.5 { v = rim * Float(cos((d - 1) / 0.5 * .pi / 2)) } // raised rim
                    hgt[y * w + x] += v
                }
            }
        }
        for _ in 0..<420 {
            let r = pow(rng.next(), 3.2) * 18 + 1.5
            add(cx: rng.next() * Double(w), cy: 10 + rng.next() * Double(h - 20), r: r,
                depth: Float(0.05 + r / 140), rim: Float(0.025 + r / 260))
        }
        return hgt
    }()

    /// Where the dark "seas" are (0 = highland, 1 = mare).
    private static func mare(_ x: Int, _ y: Int) -> Float {
        let blobs: [(Double, Double, Double)] = [(0.30, 0.38, 0.11), (0.40, 0.55, 0.09), (0.22, 0.58, 0.07),
                                                 (0.50, 0.42, 0.06), (0.62, 0.50, 0.05), (0.34, 0.68, 0.05)]
        let u = Double(x) / Double(w), v = Double(y) / Double(h)
        var m = 0.0
        for (bx, by, br) in blobs {
            let d = (((u - bx) * 1.6) * ((u - bx) * 1.6) + (v - by) * (v - by)).squareRoot() / br
            m = max(m, 1 - min(1, d * d))
        }
        return Float(m)
    }

    /// Surface brightness 0...1 (equirectangular), built once.
    static let albedoValues: [Float] = {
        var out = [Float](repeating: 0, count: w * h)
        var rng = SeededRandom(seed: 3)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                var c: Float = 0.80 - 0.30 * mare(x, y)            // highlands bright, maria dark
                c += (height[i] - 0.5) * 0.9                      // crater floors darker, rims brighter
                c += Float(rng.next() - 0.5) * 0.05               // fine regolith grain
                out[i] = max(0, min(1, c))
            }
        }
        return out
    }()

    static let albedo: UIImage = {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = UInt8(albedoValues[i] * 255)
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = UInt8(min(255, Int(v) + 4)); px[i * 4 + 3] = 255
        }
        return image(px)
    }()

    /// Brightness at a point on the near side, for flat renders. `lon`/`lat` in radians, 0,0 = disc center.
    static func sample(lon: Double, lat: Double) -> Float {
        var u = 0.4 + lon / (2 * .pi); u -= floor(u)
        let v = min(max(0.5 - lat / .pi, 0), 0.9999)
        let x = min(Int(u * Double(w)), w - 1), y = Int(v * Double(h))
        // Height slope gives a little relief near the terminator.
        return albedoValues[y * w + x]
    }

    static func slope(lon: Double, lat: Double) -> (Float, Float) {
        var u = 0.4 + lon / (2 * .pi); u -= floor(u)
        let v = min(max(0.5 - lat / .pi, 0), 0.9999)
        let x = min(Int(u * Double(w)), w - 1), y = Int(v * Double(h))
        let l = height[y * w + (x - 1 + w) % w], r = height[y * w + (x + 1) % w]
        let up = height[max(0, y - 1) * w + x], dn = height[min(h - 1, y + 1) * w + x]
        return (r - l, up - dn)
    }

    static let normal: UIImage = {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let k: Float = 6
        for y in 0..<h {
            for x in 0..<w {
                let l = height[y * w + (x - 1 + w) % w], r = height[y * w + (x + 1) % w]
                let u = height[max(0, y - 1) * w + x], d = height[min(h - 1, y + 1) * w + x]
                var nx = (l - r) * k, ny = (d - u) * k, nz: Float = 1
                let len = (nx * nx + ny * ny + nz * nz).squareRoot()
                nx /= len; ny /= len; nz /= len
                let i = (y * w + x) * 4
                px[i] = UInt8((nx * 0.5 + 0.5) * 255)
                px[i + 1] = UInt8((ny * 0.5 + 0.5) * 255)
                px[i + 2] = UInt8((nz * 0.5 + 0.5) * 255)
                px[i + 3] = 255
            }
        }
        return image(px)
    }()

    private static func image(_ px: [UInt8]) -> UIImage {
        let data = Data(px) as CFData
        let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                         space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                         provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: true,
                         intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }
}

/// Small deterministic generator so the moon looks the same every launch.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
}
