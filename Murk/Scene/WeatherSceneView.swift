import SwiftUI
import SceneKit
import UIKit
import Metal

/// Everything the 3D scene needs to know. When a field changes, only that part rebuilds.
struct SceneConfig: Equatable {
    var temperature: String
    var cover: Double
    var precip: Precip
    var intensity: Double
    var isDay: Bool
    var moonAge: Double
    var skin: Skin
    var regenToken: Int = 0
    var resetToken: Int = 0
}

/// SceneKit view with a free-rotating (arcball) camera: drag spins it any direction,
/// including fully over the top and underneath. Pinch zooms. Tap grows new clouds.
struct WeatherSceneView: UIViewRepresentable {
    var config: SceneConfig

    func makeCoordinator() -> WeatherScene { WeatherScene() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        let scene = context.coordinator
        v.scene = scene.scene
        v.pointOfView = scene.cameraNode
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = true
        v.preferredFramesPerSecond = 60
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitArcball   // no up/down limit
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.automaticTarget = false
        v.defaultCameraController.target = WeatherScene.target
        let tap = UITapGestureRecognizer(target: scene, action: #selector(WeatherScene.tapped))
        v.addGestureRecognizer(tap)
        scene.view = v
        scene.apply(config, force: true)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.apply(config)
    }
}

final class WeatherScene: NSObject {
    static let target = SCNVector3(0, 0.4, 0)
    static let home = SCNVector3(0, 0.4, 11.8)

    let scene = SCNScene()
    let cameraNode = SCNNode()
    weak var view: SCNView?

    private let root = SCNNode()
    private let cloudNode = SCNNode()
    private let orbNode = SCNNode()
    private let precipNode = SCNNode()
    private let moonLight = SCNNode()
    private var digitNode: SCNNode?
    private var last: SceneConfig?

    private let cloudMat = SCNMaterial()
    private let digitMat = SCNMaterial()
    private let moonMat = SCNMaterial()
    private let sunMat = SCNMaterial()

    /// A barely-there matte texture (strong grain reads as noise on a phone screen).
    private static let grain = """
    #pragma body
    float2 gp = floor(_surface.diffuseTexcoord * 2400.0);
    float gn = fract(sin(dot(gp, float2(12.9898, 78.233))) * 43758.5453);
    _output.color.rgb += (gn - 0.5) * 0.012;
    """

    override init() {
        super.init()
        scene.background.contents = UIColor.clear

        let cam = SCNCamera()
        cam.fieldOfView = 34
        cam.zNear = 0.1
        cam.zFar = 100
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
        resetCamera(animated: false)

        scene.rootNode.addChildNode(root)
        root.addChildNode(cloudNode)
        root.addChildNode(orbNode)
        root.addChildNode(precipNode)
        precipNode.position = SCNVector3(0, 0.9, 0)
        orbNode.position = SCNVector3(1.15, 2.45, -1.6)

        // Lights fixed in the world, so shading changes as you orbit.
        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, mask: Int, at p: SCNVector3?) -> SCNNode {
            let l = SCNLight(); l.type = type; l.intensity = intensity; l.categoryBitMask = mask
            let n = SCNNode(); n.light = l
            if let p { n.position = p; n.look(at: SCNVector3Zero) }
            return n
        }
        scene.rootNode.addChildNode(light(.directional, 1150, mask: 1, at: SCNVector3(-5, 7, 6)))   // key
        scene.rootNode.addChildNode(light(.directional, 480, mask: 1, at: SCNVector3(4, 3, -7)))    // rim
        scene.rootNode.addChildNode(light(.ambient, 150, mask: 1, at: nil))
        scene.rootNode.addChildNode(light(.ambient, 22, mask: 2, at: nil))                           // earthshine
        let ml = SCNLight(); ml.type = .directional; ml.intensity = 1300; ml.categoryBitMask = 2
        moonLight.light = ml
        scene.rootNode.addChildNode(moonLight)

        for m in [cloudMat, digitMat] {
            m.lightingModel = .physicallyBased
            m.shaderModifiers = [.fragment: Self.grain]
        }
        cloudMat.roughness.contents = 0.9
        cloudMat.metalness.contents = 0.0
        digitMat.roughness.contents = 0.42
        digitMat.metalness.contents = 0.25
        moonMat.lightingModel = .lambert
        moonMat.shaderModifiers = [.fragment: Self.grain]
        sunMat.lightingModel = .constant
    }

    // MARK: Updates

    func apply(_ c: SceneConfig, force: Bool = false) {
        let p = last
        if force || p?.skin != c.skin { applySkin(c.skin) }
        if force || p?.temperature != c.temperature { buildDigits(c.temperature) }
        if force || p?.cover != c.cover || p?.regenToken != c.regenToken { buildClouds(cover: c.cover) }
        if force || p?.precip != c.precip || p?.intensity != c.intensity || p?.skin != c.skin {
            buildPrecip(c.precip, intensity: c.intensity, skin: c.skin)
        }
        if force || p?.isDay != c.isDay || p?.moonAge != c.moonAge { buildOrb(isDay: c.isDay, moonAge: c.moonAge) }
        if let p, p.resetToken != c.resetToken { resetCamera(animated: true) }
        last = c
    }

    /// Renders just the sky (clouds + sun or moon, no digits or rain) to a still image, for widgets.
    func snapshot(cover: Double, isDay: Bool, moonAge: Double, skin: Skin, size: CGSize) -> UIImage? {
        applySkin(skin)
        digitNode?.removeFromParentNode(); digitNode = nil
        precipNode.removeAllParticleSystems()
        buildClouds(cover: cover, animated: false)
        buildOrb(isDay: isDay, moonAge: moonAge)
        scene.background.contents = UIColor(hex: skin.bgHex)
        cameraNode.position = SCNVector3(0, 2.0, 8.0)
        cameraNode.orientation = SCNQuaternion(0, 0, 0, 1)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene
        r.pointOfView = cameraNode
        let img = r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return img.keyingOut(hex: skin.bgHex)
    }

    @objc func tapped() {
        if let c = last { buildClouds(cover: c.cover) }
    }

    func resetCamera(animated: Bool) {
        // Once the user drags, SceneKit's camera control may swap in its own camera node,
        // so reset whichever node the view is actually looking through, then hand our camera back.
        let povs = [cameraNode] + [view?.pointOfView].compactMap { $0 }.filter { $0 !== cameraNode }
        view?.defaultCameraController.stopInertia()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        for n in povs {
            n.position = Self.home
            n.orientation = SCNQuaternion(0, 0, 0, 1)
            n.camera?.fieldOfView = 34
        }
        SCNTransaction.completionBlock = { [weak self] in
            guard let self, let v = self.view else { return }
            v.pointOfView = self.cameraNode
            v.defaultCameraController.target = Self.target
        }
        SCNTransaction.commit()
    }

    private func applySkin(_ s: Skin) {
        cloudMat.diffuse.contents = UIColor(hex: s.cloudHex)
        digitMat.diffuse.contents = UIColor(hex: s.digitHex)
        moonMat.diffuse.contents = UIColor(hex: s.moonHex)
        sunMat.diffuse.contents = UIColor(hex: s.sunHex)
    }

    // MARK: Builders

    private func buildDigits(_ string: String) {
        digitNode?.removeFromParentNode()
        let text = SCNText(string: string, extrusionDepth: 9)
        text.font = UIFont.systemFont(ofSize: 40, weight: .black, width: .compressed)
        text.flatness = 0.06
        text.chamferRadius = 1.6
        let profile = UIBezierPath()
        profile.move(to: CGPoint(x: 0, y: 1))
        profile.addQuadCurve(to: CGPoint(x: 1, y: 0), controlPoint: CGPoint(x: 0, y: 0))
        text.chamferProfile = profile
        text.materials = [digitMat]

        let node = SCNNode(geometry: text)
        let (mn, mx) = text.boundingBox
        let scale = 3.0 / max(mx.y - mn.y, 1)
        node.pivot = SCNMatrix4MakeTranslation((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, (mn.z + mx.z) / 2)
        node.scale = SCNVector3(scale, scale, scale)
        node.position = SCNVector3(0, -1.05, 0)
        node.opacity = 0
        root.addChildNode(node)
        node.runAction(.fadeIn(duration: 0.35))
        digitNode = node
    }

    private func buildClouds(cover: Double, animated: Bool = true) {
        cloudNode.childNodes.forEach { $0.removeFromParentNode() }
        var puffs: [(SCNVector3, CGFloat)] = []
        let count = max(3, Int((cover * 21).rounded()))
        for _ in 0..<count {
            let x = Double.random(in: -1.75...1.75)
            let mid = 1 - abs(x) / 1.9
            let y = 1.25 + Double.random(in: 0...0.35) + mid * 0.75 * Double.random(in: 0...1)
            let z = Double.random(in: -0.55...0.55)
            let r = 0.22 + Double.random(in: 0...0.25) + mid * 0.45 * (0.6 + cover * 0.6)
            puffs.append((SCNVector3(Float(x), Float(y), Float(z)), CGFloat(r)))
        }
        for _ in 0..<(cover > 0.2 ? 4 : 1) {
            let side: Double = Bool.random() ? -1 : 1
            puffs.append((SCNVector3(Float(side * Double.random(in: 1.7...2.2)), Float(Double.random(in: 0.95...1.35)), Float(Double.random(in: -0.3...0.3))),
                          CGFloat(Double.random(in: 0.09...0.19))))
        }
        for (i, puff) in puffs.enumerated() {
            let sphere = SCNSphere(radius: puff.1)
            sphere.segmentCount = 48
            sphere.materials = [cloudMat]
            let n = SCNNode(geometry: sphere)
            n.position = puff.0
            guard animated else { cloudNode.addChildNode(n); continue }
            n.scale = SCNVector3(0.001, 0.001, 0.001)

            let grow = SCNAction.scale(to: 1, duration: 0.5)
            grow.timingFunction = { t in   // ease-out with a little overshoot
                let c: Float = 1.7, u = t - 1
                return 1 + (c + 1) * u * u * u + c * u * u
            }
            n.runAction(.sequence([.wait(duration: Double(i) * 0.035), grow]))

            let d = Double.random(in: 2.4...3.6)
            let drift = SCNAction.sequence([.moveBy(x: 0, y: 0.05, z: 0, duration: d), .moveBy(x: 0, y: -0.05, z: 0, duration: d)])
            drift.timingMode = .easeInEaseOut
            n.runAction(.repeatForever(drift))
            cloudNode.addChildNode(n)
        }
    }

    private func buildPrecip(_ kind: Precip, intensity: Double, skin: Skin) {
        precipNode.removeAllParticleSystems()
        guard kind != .none, intensity > 0 else { return }
        let snow = kind == .snow
        let ps = SCNParticleSystem()
        ps.emitterShape = SCNBox(width: 3.8, height: 0.01, length: 1.8, chamferRadius: 0)
        ps.birthLocation = .volume
        ps.emittingDirection = SCNVector3(0, -1, 0)
        ps.spreadingAngle = snow ? 25 : 3
        ps.particleLifeSpan = snow ? 3.4 : 0.9
        ps.particleVelocity = snow ? 0.9 : 4.2
        ps.particleVelocityVariation = snow ? 0.3 : 0.8
        ps.birthRate = CGFloat(intensity * (snow ? 90 : 240))
        ps.particleSize = snow ? 0.035 : 0.012
        ps.stretchFactor = snow ? 0 : 0.06
        ps.particleColor = snow ? .white : UIColor(hex: skin.rainHex)
        ps.particleImage = Self.dot
        ps.blendMode = .alpha
        ps.isLightingEnabled = false
        precipNode.addParticleSystem(ps)
    }

    private static let dot: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { ctx in
        UIColor.white.setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 16, height: 16))
    }

    private func buildOrb(isDay: Bool, moonAge: Double) {
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 64
        if isDay {
            sphere.materials = [sunMat]
            orbNode.categoryBitMask = 1
        } else {
            // Light the moon from where the sun really is, so the lit part matches tonight's phase.
            sphere.materials = [moonMat]
            orbNode.categoryBitMask = 2
            let th = 2 * Double.pi * moonAge / Astronomy.synodicMonth
            let o = orbNode.position
            moonLight.position = SCNVector3(o.x + Float(sin(th)) * 10, o.y + 0.8, o.z - Float(cos(th)) * 10)
            moonLight.look(at: o)
        }
        orbNode.geometry = sphere
    }
}


extension UIImage {
    /// Makes pixels close to `hex` transparent (soft edge), so the sky has no background square.
    func keyingOut(hex: UInt32) -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let kr = Double((hex >> 16) & 0xFF), kg = Double((hex >> 8) & 0xFF), kb = Double(hex & 0xFF)
        for i in stride(from: 0, to: px.count, by: 4) {
            let dr = Double(px[i]) - kr, dg = Double(px[i + 1]) - kg, db = Double(px[i + 2]) - kb
            let d = (dr * dr + dg * dg + db * db).squareRoot()
            let a = min(1, max(0, (d - 5) / 30))
            if a < 1 {
                px[i] = UInt8(Double(px[i]) * a)
                px[i + 1] = UInt8(Double(px[i + 1]) * a)
                px[i + 2] = UInt8(Double(px[i + 2]) * a)
                px[i + 3] = UInt8(255 * a)
            }
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: scale, orientation: imageOrientation)
    }
}
