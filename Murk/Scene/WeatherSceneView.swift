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
    var windSpeed: Double = 0        // km/h
    var windDirection: Double = 0    // degrees the wind comes FROM
    var thunder = false
    var sunAltitude: Double = 45     // degrees, rounded by the caller
    var sunRising = true             // morning (dawn colors) vs afternoon (dusk colors)
    var moonAltitude: Double = 45    // degrees above the horizon, rounded by the caller
    var moonRising = true
    var regenToken: Int = 0
    var resetToken: Int = 0
}

/// SceneKit view with a free-rotating (arcball) camera: drag spins it any direction,
/// including fully over the top and underneath. Pinch zooms. Tap grows new clouds.
struct WeatherSceneView: UIViewRepresentable {
    var config: SceneConfig
    /// False while the page is off screen or the app is inactive: rendering stops.
    var active = true
    /// Reduce Motion: no drifting, swaying or pulsing.
    var calm = false
    var onThunder: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> WeatherScene { WeatherScene() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        let scene = context.coordinator
        v.scene = scene.scene
        v.pointOfView = scene.cameraNode
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.rendersContinuously = false
        v.preferredFramesPerSecond = 30
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitArcball   // no up/down limit
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.automaticTarget = false
        v.defaultCameraController.target = WeatherScene.target
        let tap = UITapGestureRecognizer(target: scene, action: #selector(WeatherScene.tapped))
        v.addGestureRecognizer(tap)
        // Full frame rate only while a finger is on the scene (and briefly after, for the spin to settle).
        let touch = UILongPressGestureRecognizer(target: scene, action: #selector(WeatherScene.touched(_:)))
        touch.minimumPressDuration = 0
        touch.cancelsTouchesInView = false
        touch.delegate = scene
        v.addGestureRecognizer(touch)
        scene.view = v
        scene.calm = calm
        scene.apply(config, force: true)
        scene.setActive(active)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.onThunder = onThunder
        context.coordinator.onTap = onTap
        let motionChanged = context.coordinator.calm != calm
        context.coordinator.calm = calm
        context.coordinator.apply(config, force: motionChanged)
        context.coordinator.setActive(active)
    }
}

final class WeatherScene: NSObject, UIGestureRecognizerDelegate {
    var calm = false
    private var isActive = true
    private var settle: DispatchWorkItem?

    /// Stops or resumes drawing. A paused scene uses no GPU.
    func setActive(_ on: Bool) {
        guard on != isActive || view?.isPlaying != on else { return }
        isActive = on
        scene.isPaused = !on
        view?.isPlaying = on
        if on { applyFrameRate() }
    }

    /// 30 fps for drifting clouds; 60 for rain, snow and storms, or while being spun.
    private func applyFrameRate(interacting: Bool = false) {
        let busy = (last?.precip ?? .none) != .none || last?.thunder == true
        view?.preferredFramesPerSecond = (interacting || busy) && !calm ? 60 : 30
    }

    @objc func touched(_ g: UIGestureRecognizer) {
        settle?.cancel()
        switch g.state {
        case .began, .changed:
            applyFrameRate(interacting: true)
        default:
            let work = DispatchWorkItem { [weak self] in self?.applyFrameRate() }
            settle = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    static let target = SCNVector3(0, 0.4, 0)
    static let home = SCNVector3(0, 0.4, 11.8)

    let scene = SCNScene()
    let cameraNode = SCNNode()
    weak var view: SCNView?

    private let root = SCNNode()
    private let cloudNode = SCNNode()
    private let orbNode = SCNNode()
    private let starNode = SCNNode()
    private let precipNode = SCNNode()
    private let moonLight = SCNNode()
    private let keyLight = SCNNode()
    private let rimLight = SCNNode()
    private let ambLight = SCNNode()
    private let flashLight = SCNNode()
    private var digitNode: SCNNode?
    var onThunder: (() -> Void)?
    var onTap: (() -> Void)?
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

    private static let white: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { ctx in
        UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    private static let sunShader = """
    float sunHash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }
    float sunNoise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(sunHash(i), sunHash(i + float2(1, 0)), f.x),
                   mix(sunHash(i + float2(0, 1)), sunHash(i + float2(1, 1)), f.x), f.y);
    }
    #pragma body
    float mu = clamp(dot(normalize(_surface.normal), float3(0.0, 0.0, 1.0)), 0.0, 1.0);
    float2 uv = _surface.diffuseTexcoord * float2(48.0, 24.0);
    float t = scn_frame.time * 0.08;
    float gran = sunNoise(uv + t) * 0.6 + sunNoise(uv * 2.3 - t * 1.3) * 0.4;
    float3 base = _output.color.rgb;
    float3 c = base * (0.42 + 0.58 * pow(mu, 0.55));          // limb darkening
    c = mix(c, float3(1.0, 0.98, 0.9), pow(mu, 3.0) * 0.45);  // white-hot core
    c *= 0.9 + 0.2 * gran;                                    // granulation
    _output.color.rgb = c;
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
        starNode.geometry = Self.makeStars()
        starNode.isHidden = true
        scene.rootNode.addChildNode(starNode)
        precipNode.position = SCNVector3(0, 0.9, 0)
        orbNode.position = SCNVector3(1.15, 2.45, -1.6)

        // Lights fixed in the world, so shading changes as you orbit.
        func light(_ type: SCNLight.LightType, _ intensity: CGFloat, mask: Int, at p: SCNVector3?) -> SCNNode {
            let l = SCNLight(); l.type = type; l.intensity = intensity; l.categoryBitMask = mask
            let n = SCNNode(); n.light = l
            if let p { n.position = p; n.look(at: SCNVector3Zero) }
            return n
        }
        for (node, src) in [(keyLight, light(.directional, 1150, mask: 1, at: SCNVector3(-5, 7, 6))),
                            (rimLight, light(.directional, 480, mask: 1, at: SCNVector3(4, 3, -7))),
                            (ambLight, light(.ambient, 150, mask: 1, at: nil))] {
            node.light = src.light; node.position = src.position; node.orientation = src.orientation
            scene.rootNode.addChildNode(node)
        }
        let fl = SCNLight(); fl.type = .omni; fl.intensity = 0; fl.categoryBitMask = 1
        fl.color = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1); fl.attenuationEndDistance = 6
        flashLight.light = fl; flashLight.position = SCNVector3(0, 1.6, 0.4)
        root.addChildNode(flashLight)
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
        // Moon: cratered surface lit for tonight's phase (see MoonLook).
        MoonLook.configure(moonMat)
        // Sun: glowing plasma with limb darkening (bright core, deeper-colored edge) and slow granulation.
        sunMat.lightingModel = .constant
        sunMat.shaderModifiers = [.fragment: Self.sunShader]
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
        if force || p?.isDay != c.isDay || p?.moonAge != c.moonAge || p?.sunAltitude != c.sunAltitude || p?.sunRising != c.sunRising || p?.skin != c.skin
            || p?.moonAltitude != c.moonAltitude || p?.moonRising != c.moonRising {
            buildOrb(isDay: c.isDay, moonAge: c.moonAge, sunAltitude: c.sunAltitude, rising: c.sunRising,
                     moonAltitude: c.moonAltitude, moonRising: c.moonRising, skin: c.skin, animated: p != nil)
            applyTimeOfDay(c.isDay ? c.sunAltitude : min(c.sunAltitude, -8))
        }
        if force || p?.isDay != c.isDay || p?.cover != c.cover || p?.precip != c.precip {
            showStars(!c.isDay, cover: c.cover, precip: c.precip != .none)
        }
        if force || p?.isDay != c.isDay || p?.cover != c.cover || p?.precip != c.precip || p?.skin != c.skin || p?.sunAltitude != c.sunAltitude {
            applySkyTint(c)
        }
        if force || p?.windSpeed != c.windSpeed || p?.windDirection != c.windDirection || p?.precip != c.precip || p?.intensity != c.intensity {
            applyWind(speed: c.windSpeed, from: c.windDirection)
        }
        if force || p?.thunder != c.thunder { setThunder(c.thunder) }
        if let p, p.resetToken != c.resetToken { resetCamera(animated: true) }
        last = c
        applyFrameRate()
    }

    /// Renders just the sky (clouds + sun or moon, no digits or rain) to a still image, for widgets.
    func snapshot(cover: Double, isDay: Bool, moonAge: Double, skin: Skin, size: CGSize) -> UIImage? {
        applySkin(skin)
        // Lighter clouds so they read on any widget background; by day dark skins get the sunlit white clouds.
        cloudMat.diffuse.contents = UIColor(hex: skin.cloudHex).blended(toward: .white, by: isDay && !skin.isLight ? 0.82 : 0.28)
        digitNode?.removeFromParentNode(); digitNode = nil
        precipNode.removeAllParticleSystems()
        starNode.isHidden = true
        buildClouds(cover: cover, animated: false)
        buildOrb(isDay: isDay, moonAge: moonAge, sunAltitude: 45, skin: skin, glow: false, fixed: true)
        scene.background.contents = UIColor(red: 0, green: 1, blue: 0, alpha: 1)   // chroma key: nothing in the sky is green
        cameraNode.position = SCNVector3(0, 2.0, 8.0)
        cameraNode.orientation = SCNQuaternion(0, 0, 0, 1)
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene
        r.pointOfView = cameraNode
        let img = r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return img.keyingOutGreen()
    }

    @objc func tapped() {
        if let c = last { buildClouds(cover: c.cover) }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onTap?()
    }

    /// Full-scene still (clouds, digits, sun/moon) sized for a phone wallpaper.
    func wallpaper(_ c: SceneConfig, size: CGSize) -> UIImage? {
        apply(c, force: true)
        precipNode.removeAllParticleSystems()
        scene.background.contents = UIColor(hex: c.skin.bgHex)
        let cam = SCNNode(); let camera = SCNCamera(); camera.fieldOfView = 34; camera.zFar = 100
        cam.camera = camera
        let aspect = Float(size.width / size.height)
        let dist = max(7.0 / (2 * tan(17 * Float.pi / 180)), 5.2 / (2 * tan(17 * Float.pi / 180) * aspect))
        cam.position = SCNVector3(0, 1.4, dist)
        scene.rootNode.addChildNode(cam)
        defer { cam.removeFromParentNode() }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let r = SCNRenderer(device: device, options: nil)
        r.scene = scene; r.pointOfView = cam
        return r.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    }

    // MARK: Atmosphere

    /// Warm light at dawn/dusk, white at midday; at night a soft blue fill plus
    /// silver moonlight from behind the clouds, so their edges glow.
    private func applyTimeOfDay(_ alt: Double) {
        let night = alt < -4
        let key: (UIColor, CGFloat), amb: (UIColor, CGFloat)
        switch alt {
        case ..<(-4):  key = (UIColor(red: 0.62, green: 0.72, blue: 1.0, alpha: 1), 700); amb = (UIColor(red: 0.62, green: 0.72, blue: 1, alpha: 1), 240)
        case ..<4:     key = (UIColor(red: 1.0, green: 0.55, blue: 0.38, alpha: 1), 820); amb = (UIColor(red: 0.9, green: 0.7, blue: 0.75, alpha: 1), 130)
        case ..<15:    key = (UIColor(red: 1.0, green: 0.8, blue: 0.58, alpha: 1), 1000); amb = (UIColor(red: 1, green: 0.92, blue: 0.85, alpha: 1), 140)
        default:       key = (.white, 1150); amb = (.white, 150)
        }
        // Moonlight comes from where the moon sits (up and behind); by day the rim light is back in its usual spot.
        let rimAt = SCNVector3(4.6, night ? 8.5 : Float(2.5 + min(max(alt, 0), 60) / 10), -7.5)
        SCNTransaction.begin(); SCNTransaction.animationDuration = 1.2
        keyLight.light?.color = key.0; keyLight.light?.intensity = key.1
        ambLight.light?.color = amb.0; ambLight.light?.intensity = amb.1
        let golden = UIColor(red: 1, green: 0.84, blue: 0.58, alpha: 1)
        rimLight.light?.color = night ? UIColor(red: 0.86, green: 0.91, blue: 1, alpha: 1) : key.0.blended(toward: golden, by: 0.6)
        rimLight.light?.intensity = night ? 1700 : 1500
        if !night { ambLight.light?.color = amb.0.blended(toward: UIColor(red: 0.72, green: 0.8, blue: 0.95, alpha: 1), by: 0.5) }
        rimLight.position = rimAt
        rimLight.look(at: SCNVector3Zero)
        // A faint blue glow keeps dark skins readable at night.
        cloudMat.emission.contents = night ? UIColor(red: 0.09, green: 0.12, blue: 0.22, alpha: 1) : UIColor.black
        digitMat.emission.contents = night ? UIColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1) : UIColor.black
        SCNTransaction.commit()
    }

    /// On a bright sky, dark-skin clouds turn white with a soft blue shade and the digits go slate,
    /// like the sunny-day look. Overcast keeps them grey; light skins keep their own colors.
    private func applySkyTint(_ c: SceneConfig) {
        let s = c.skin
        let grey = c.precip != .none ? 1 : min(1, max(0, (c.cover - 0.5) / 0.4))
        let dayness = c.isDay ? min(1, max(0, (c.sunAltitude + 2) / 10)) : 0
        let t = s.isLight ? 0 : CGFloat(dayness * (1 - grey * 0.55))
        let cloudDay = UIColor(red: 0.95, green: 0.95, blue: 0.94, alpha: 1)
        let digitDay = UIColor(hex: 0x2B3F5C)
        SCNTransaction.begin(); SCNTransaction.animationDuration = 1.0
        cloudMat.diffuse.contents = UIColor(hex: s.cloudHex).blended(toward: cloudDay, by: t * 0.92)
        digitMat.diffuse.contents = UIColor(hex: s.digitHex).blended(toward: digitDay, by: t)
        SCNTransaction.commit()
    }

    /// Stars all around the scene; clouds and rain thin them out.
    private func showStars(_ on: Bool, cover: Double, precip: Bool) {
        let target: CGFloat = on ? CGFloat(max(0.18, 1 - cover * 0.85) * (precip ? 0.4 : 1)) : 0
        if on { starNode.isHidden = false }
        starNode.removeAction(forKey: "fade")
        starNode.runAction(.sequence([.fadeOpacity(to: target, duration: 1.0),
                                      .run { n in if target == 0 { n.isHidden = true } }]), forKey: "fade")
    }

    /// ~900 points on a big sphere, with varied brightness and a gentle twinkle.
    private static func makeStars() -> SCNGeometry {
        var verts: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        for _ in 0..<900 {
            // Uniform on a sphere.
            let z = Float.random(in: -1...1), t = Float.random(in: 0..<(2 * .pi))
            let r = (1 - z * z).squareRoot()
            verts.append(SCNVector3(r * cos(t) * 32, z * 32, r * sin(t) * 32))
            let b = pow(Float.random(in: 0.15...1), 2.2)
            let warm = Float.random(in: 0...1)
            colors.append(SIMD4(b * (0.85 + 0.15 * warm), b * 0.92, b * (1.0 - 0.15 * warm), 1))
        }
        let vsrc = SCNGeometrySource(vertices: verts)
        let cdata = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let csrc = SCNGeometrySource(data: cdata, semantic: .color, vectorCount: colors.count,
                                     usesFloatComponents: true, componentsPerVector: 4,
                                     bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                     dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let el = SCNGeometryElement(indices: Array(0..<Int32(verts.count)), primitiveType: .point)
        el.pointSize = 3
        el.minimumPointScreenSpaceRadius = 0.8
        el.maximumPointScreenSpaceRadius = 2.6
        let g = SCNGeometry(sources: [vsrc, csrc], elements: [el])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.writesToDepthBuffer = false
        m.blendMode = .add
        m.shaderModifiers = [.fragment: """
        #pragma body
        float ph = fract(_surface.diffuse.r * 91.7 + _surface.diffuse.b * 37.3) * 6.2831;
        _output.color.rgb *= 0.65 + 0.35 * sin(scn_frame.time * 1.7 + ph);
        """]
        g.materials = [m]
        return g
    }

    /// Clouds drift and rain slants with the wind.
    private func applyWind(speed: Double, from dir: Double) {
        let w = min(1, max(0, speed / 45))
        let toward = (dir + 180) * Double.pi / 180
        let xs = Float(sin(toward)) * Float(w)              // east-west push on screen
        cloudNode.removeAction(forKey: "wind")
        if w > 0.05 && !calm {
            let amp = CGFloat(0.12 + 0.45 * w) * (xs >= 0 ? 1 : -1)
            let d = 7.0 / (0.4 + w)
            let sway = SCNAction.sequence([.moveBy(x: amp, y: 0, z: 0, duration: d), .moveBy(x: -amp, y: 0, z: 0, duration: d)])
            sway.timingMode = .easeInEaseOut
            cloudNode.runAction(.repeatForever(sway), forKey: "wind")
        } else {
            cloudNode.runAction(.move(to: SCNVector3Zero, duration: 1))
        }
        for ps in precipNode.particleSystems ?? [] {
            ps.emittingDirection = SCNVector3(xs * 0.7, -1, 0)
            ps.acceleration = SCNVector3(xs * 4, 0, 0)
        }
    }

    /// Lightning: random flickers inside the clouds while a storm is on.
    private func setThunder(_ on: Bool) {
        flashLight.removeAction(forKey: "storm")
        flashLight.light?.intensity = 0
        guard on else { return }
        let flash = SCNAction.customAction(duration: 0.55) { node, t in
            let k = Double(t / 0.55)
            let i = k < 0.12 ? 1 : (k < 0.22 ? 0.15 : (k < 0.32 ? 0.8 : max(0, 1 - (k - 0.32) / 0.68)))
            node.light?.intensity = CGFloat(i * 5200)
        }
        let strike = SCNAction.sequence([
            .run { [weak self] node in
                node.position = SCNVector3(Float.random(in: -1.2...1.2), Float.random(in: 1.3...2.0), 0.4)
                DispatchQueue.main.async { self?.onThunder?() }
            },
            flash,
            .wait(duration: 4, withRange: 6)
        ])
        flashLight.runAction(.sequence([.wait(duration: 1.5), .repeatForever(strike)]), forKey: "storm")
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
        MoonLook.setTint(UIColor(hex: s.moonHex), on: moonMat)
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
            if !calm { n.runAction(.repeatForever(drift)) }
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

    /// Sun color through the day: reddish-yellow at dawn, yellow by midday, red at dusk.
    static func sunColor(altitude: Double, rising: Bool) -> UIColor {
        let dawn = UIColor(red: 1.0, green: 0.56, blue: 0.22, alpha: 1)    // reddish yellow
        let noon = UIColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)     // yellow
        let dusk = UIColor(red: 0.93, green: 0.25, blue: 0.16, alpha: 1)   // red
        let t = CGFloat(min(1, max(0, altitude / 35)))
        let eased = t * t * (3 - 2 * t)
        return (rising ? dawn : dusk).blended(toward: noon, by: eased)
    }

    /// Where a body sits on its arc: rises on the left (east), peaks overhead behind the clouds,
    /// sets on the right (west), and sinks below the cloud base as it goes under the horizon.
    static func arcPosition(altitude: Double, rising: Bool) -> SCNVector3 {
        let h = min(max(altitude, -8), 65) / 65
        let up = max(h, 0)
        let side: Float = rising ? -1 : 1
        let x = side * 2.6 * Float(pow(1 - up, 0.85))
        let y = 0.55 + 2.05 * Float(sin(up * .pi / 2)) + (h < 0 ? Float(h) * 6 : 0)
        return SCNVector3(x, y, -1.9)
    }

    private func buildOrb(isDay: Bool, moonAge: Double, sunAltitude: Double, rising: Bool = true,
                          moonAltitude: Double = 45, moonRising: Bool = false,
                          skin: Skin, glow: Bool = true, fixed: Bool = false, animated: Bool = false) {
        orbNode.childNodes.forEach { $0.removeFromParentNode() }
        let sphere = SCNSphere(radius: 0.85)
        sphere.segmentCount = 96
        let alt = isDay ? sunAltitude : moonAltitude
        let target = fixed ? SCNVector3(1.15, 2.45, -1.6) : Self.arcPosition(altitude: alt, rising: isDay ? rising : moonRising)
        // Fade out as it slips under the horizon.
        let opacity = fixed ? 1 : CGFloat(min(1, max(0, (alt + 3) / 5)))
        SCNTransaction.begin(); SCNTransaction.animationDuration = animated ? 1.2 : 0
        orbNode.position = target
        orbNode.opacity = opacity
        SCNTransaction.commit()
        if isDay {
            sphere.materials = [sunMat]
            orbNode.categoryBitMask = 1
            let sunColor = Self.sunColor(altitude: sunAltitude, rising: rising)
            sunMat.diffuse.contents = Self.white
            sunMat.multiply.contents = sunColor
            if glow { addSunGlow(color: sunColor) }
        } else {
            // The terminator is computed in the shader from the moon's age, so the phase is always right.
            sphere.materials = [moonMat]
            orbNode.categoryBitMask = 8      // no scene lights; MoonLook does its own lighting
            MoonLook.setAge(moonAge, on: moonMat)
            if glow { addMoonGlow(illumination: Astronomy.illumination(age: moonAge)) }
        }
        orbNode.geometry = sphere
        orbNode.removeAction(forKey: "spin")
        orbNode.eulerAngles = SCNVector3(0, isDay ? orbNode.eulerAngles.y : -.pi / 2, 0)   // moon shows its near side
        if !fixed && isDay && !calm { orbNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 240)), forKey: "spin") }
    }
}


extension WeatherScene {
    /// A soft pulsing halo and slowly turning rays around the sun, always facing the camera.
    fileprivate func addSunGlow(color: UIColor) {
        let holder = SCNNode()
        holder.constraints = [SCNBillboardConstraint()]
        holder.position = SCNVector3(0, 0, -0.05)
        func plane(_ size: CGFloat, _ img: UIImage, _ opacity: CGFloat) -> SCNNode {
            let g = SCNPlane(width: size, height: size)
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = img
            m.multiply.contents = color.blended(toward: .white, by: 0.45)
            m.blendMode = .add
            m.writesToDepthBuffer = false
            m.isDoubleSided = true
            g.materials = [m]
            let n = SCNNode(geometry: g); n.opacity = opacity; n.categoryBitMask = 4
            return n
        }
        // Two soft layers: a tight bright corona and a wide faint bloom.
        let corona = plane(3.2, Self.haloImage, 0.9)
        let bloom = plane(7.5, Self.haloImage, 0.35)
        let pulse = SCNAction.sequence([.scale(to: 1.04, duration: 3.2), .scale(to: 0.97, duration: 3.2)])
        pulse.timingMode = .easeInEaseOut
        if !calm { corona.runAction(.repeatForever(pulse)) }
        holder.addChildNode(bloom)
        holder.addChildNode(corona)
        // Glow sits behind the sun disc (orb sphere radius 1 inside a 5-wide halo).
        holder.renderingOrder = -1
        orbNode.addChildNode(holder)
    }

    /// A faint silver glow around the moon.
    fileprivate func addMoonGlow(illumination k: Double) {
        let g = SCNPlane(width: 3.4, height: 3.4)
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Self.haloImage
        m.multiply.contents = UIColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        g.materials = [m]
        let n = SCNNode(geometry: g)
        // Only the lit part glows, so a thin crescent gets a faint halo and a full moon a bright one.
        n.opacity = CGFloat(0.05 + 0.27 * k)
        n.scale = SCNVector3(0.8 + 0.2 * k, 0.8 + 0.2 * k, 1)
        n.categoryBitMask = 4
        n.constraints = [SCNBillboardConstraint()]
        orbNode.addChildNode(n)
    }

    fileprivate static let haloImage: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0.35).cgColor,
                      UIColor(white: 1, alpha: 0.08).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.3, 0.62, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                                         endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [])
    }

}

extension UIColor {
    func blended(toward other: UIColor, by t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t, blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}

extension UIImage {
    /// Removes a pure-green background (soft edges, with green spill cleaned off the edge pixels).
    func keyingOutGreen() -> UIImage? {
        guard let cg = cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        for i in stride(from: 0, to: px.count, by: 4) {
            let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
            let spill = g - max(r, b)          // how much greener than the scene this pixel is
            guard spill > 8 else { continue }
            let a = max(0, min(1, 1 - (spill - 8) / 200))
            let g2 = min(g, max(r, b))         // despill
            px[i] = UInt8(r * a); px[i + 1] = UInt8(g2 * a); px[i + 2] = UInt8(b * a); px[i + 3] = UInt8(255 * a)
        }
        guard let out = ctx.makeImage() else { return nil }
        return UIImage(cgImage: out, scale: scale, orientation: imageOrientation)
    }
}
