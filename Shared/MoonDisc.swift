import SwiftUI

/// Moon disc with the correct lit portion for a given age.
struct MoonDisc: View {
    let age: Double
    var lit: Color
    var dark: Color

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(dark))
            ctx.fill(MoonDisc.litPath(center: c, r: r, age: age), with: .color(lit))
        }
    }

    static func litPath(center c: CGPoint, r: CGFloat, age: Double) -> Path {
        let k = Astronomy.illumination(age: age)
        let waxing = age < Astronomy.synodicMonth / 2
        let rx = abs(1 - 2 * k) * r
        var p = Path()
        // Outer limb: half circle on the lit side, top → bottom
        let side: CGFloat = waxing ? 1 : -1
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        for i in 0...40 {
            let a = -Double.pi / 2 + Double(i) / 40 * Double.pi
            p.addLine(to: CGPoint(x: c.x + side * r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
        }
        // Terminator (half ellipse back to the top)
        let bulgeTowardLit = k < 0.5
        let sign: CGFloat = (waxing == bulgeTowardLit) ? 1 : -1   // +1 bulges right
        let steps = 40
        for i in 0...steps {
            let t = Double(i) / Double(steps)          // 0 bottom … 1 top
            let a = Double.pi / 2 - t * Double.pi      // 90° … -90°
            p.addLine(to: CGPoint(x: c.x + sign * rx * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
        }
        p.closeSubpath()
        return p
    }
}
