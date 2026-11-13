import SceneKit
import UIKit

/// The moon's material: cratered albedo and relief, lit by a shader that places the terminator
/// from the moon's age. The light direction is fixed relative to the viewer, so the phase you see
/// is tonight's phase from any angle — waxing lit on the right, waning on the left.
enum MoonLook {
    private static let shader = """
    #pragma arguments
    float3 moonSun;
    float3 moonTint;
    float3 moonSky;
    float moonDay;
    #pragma body
    float3 n = normalize(_surface.normal);
    float3 L = normalize(moonSun);
    float d = dot(n, L);
    float lit = smoothstep(-0.03, 0.09, d);                    // soft terminator
    float shade = mix(0.5, 1.0, sqrt(clamp(d, 0.0, 1.0)));     // the moon stays bright almost to the edge
    float3 alb = _surface.diffuse.rgb;
    float3 sunlit = alb * moonTint * lit * shade * 1.15;
    float3 earthshine = alb * float3(0.035, 0.042, 0.06);      // the faint glow on the dark part
    float3 night = sunlit + earthshine;
    // By day the unlit part takes the sky's color (it vanishes, like the real daytime moon),
    // and the lit part is a pale, slightly blue-washed white.
    float3 day = mix(moonSky + alb * 0.04, mix(alb * moonTint * shade * 1.05, moonSky, 0.18), lit);
    _output.color = float4(mix(night, day, moonDay), 1.0);
    """

    static func configure(_ m: SCNMaterial) {
        m.lightingModel = .lambert
        m.diffuse.contents = MoonSurface.albedo
        m.normal.contents = MoonSurface.normal
        m.normal.intensity = 0.9
        m.shaderModifiers = [.fragment: shader]
        setTint(.white, on: m)
        setDaySky(nil, on: m)
        setAge(Astronomy.moonAge(), on: m)
    }

    /// Direction to the sun in view space for a given moon age (0 new … 14.8 full … 29.5 new).
    static func sunDirection(age: Double) -> SCNVector3 {
        let th = 2 * Double.pi * age / Astronomy.synodicMonth
        // sin(th) > 0 while waxing → light from the right; cos(th) = 1 at new moon → light from behind.
        return SCNVector3(Float(sin(th)), Float(-0.12 * abs(sin(th))), Float(-cos(th)))
    }

    static func setAge(_ age: Double, on m: SCNMaterial) {
        m.setValue(NSValue(scnVector3: sunDirection(age: age)), forKey: "moonSun")
    }

    static func setTint(_ c: UIColor, on m: SCNMaterial) {
        var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        m.setValue(NSValue(scnVector3: SCNVector3(Float(r), Float(g), Float(b))), forKey: "moonTint")
    }
}

extension MoonLook {
    /// Pass the sky color behind the moon by day (nil at night).
    static func setDaySky(_ c: UIColor?, on m: SCNMaterial) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        c?.getRed(&r, green: &g, blue: &b, alpha: &a)
        m.setValue(NSValue(scnVector3: SCNVector3(Float(r), Float(g), Float(b))), forKey: "moonSky")
        m.setValue(NSNumber(value: c == nil ? 0 : 1), forKey: "moonDay")
    }
}
