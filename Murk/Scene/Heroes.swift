import SwiftUI
import SceneKit
import UIKit

/// A small SceneKit world shown at the top of a page.
class HeroScene: ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let target: SCNVector3
    let home: SCNVector3
    /// True while something moves on its own (particles, swaying), so the view keeps drawing.
    var animating = true
    var calm = false { didSet { if calm != oldValue { calmChanged() } } }

    init(home: SCNVector3, target: SCNVector3, fov: CGFloat = 34) {
        self.home = home
        self.target = target
        scene.background.contents = UIColor.clear
        let cam = SCNCamera()
        cam.fieldOfView = fov
        cam.zNear = 0.1
        cam.zFar = 80
        cameraNode.camera = cam
        cameraNode.position = home
        cameraNode.look(at: target)
        scene.rootNode.addChildNode(cameraNode)
    }

    func calmChanged() {}

    static func light(_ type: SCNLight.LightType, _ intensity: CGFloat, color: UIColor = .white) -> SCNLight {
        let l = SCNLight(); l.type = type; l.intensity = intensity; l.color = color
        return l
    }

    static func pbr(_ color: UIColor, rough: CGFloat = 0.8, metal: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.roughness.contents = rough
        m.metalness.contents = metal
        return m
    }

    /// A soft round dot for particles.
    static let dot: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { ctx in
        let cs = CGColorSpaceCreateDeviceRGB()
        let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
    }

    static let halo: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128)).image { ctx in
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor(white: 1, alpha: 0.9).cgColor, UIColor(white: 1, alpha: 0.25).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.35, 1])!
        ctx.cgContext.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
    }
}

/// Hosts a `HeroScene`: spin and pinch like the Now page, double-tap to reset, paused when off screen.
struct Hero3DView: UIViewRepresentable {
    let hero: HeroScene
    var active: Bool
    var label: String

    final class Coordinator: NSObject {
        var hero: HeroScene?
        weak var view: SCNView?
        @objc func reset() {
            guard let hero, let v = view else { return }
            v.defaultCameraController.stopInertia()
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            for n in [hero.cameraNode, v.pointOfView].compactMap({ $0 }) {
                n.position = hero.home
                n.look(at: hero.target)
            }
            SCNTransaction.completionBlock = { v.pointOfView = hero.cameraNode; v.defaultCameraController.target = hero.target }
            SCNTransaction.commit()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = hero.scene
        v.pointOfView = hero.cameraNode
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 30
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.defaultCameraController.automaticTarget = false
        v.defaultCameraController.target = hero.target
        v.cameraControlConfiguration.allowsTranslation = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.reset))
        tap.numberOfTapsRequired = 2
        v.addGestureRecognizer(tap)
        v.isAccessibilityElement = true
        context.coordinator.hero = hero
        context.coordinator.view = v
        apply(v)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        context.coordinator.hero = hero
        apply(v)
    }

    private func apply(_ v: SCNView) {
        v.accessibilityLabel = label
        v.accessibilityHint = String(localized: "A 3D scene. Drag to turn it, double tap to reset.")
        v.accessibilityTraits = .image
        v.scene?.isPaused = !active
        v.isPlaying = active && hero.animating
        v.rendersContinuously = false
    }
}

// MARK: - Rain: a glass gauge under a raining cloud

final class RainHero: HeroScene {
    private let liquid = SCNNode()
    private let surface = SCNNode()
    private let cloud = SCNNode()
    private let precip = SCNNode()
    private let glint = SCNNode()
    private let liquidMat = HeroScene.pbr(UIColor(hex: 0x3EA0FF), rough: 0.15)
    private let cloudMat = SCNMaterial()
    private var last: (Double, Double, Bool)?
    static let innerHeight: CGFloat = 2.2

    init() {
        // Far enough back that the cloud over the gauge stays inside the frame.
        super.init(home: SCNVector3(0, 2.0, 10.8), target: SCNVector3(0, 1.75, 0))
        let root = scene.rootNode

        let key = SCNNode(); key.light = Self.light(.directional, 1100)
        key.light?.castsShadow = true; key.light?.shadowRadius = 4; key.light?.shadowColor = UIColor(white: 0, alpha: 0.35)
        key.position = SCNVector3(-4, 7, 5); key.look(at: SCNVector3Zero); root.addChildNode(key)
        let rim = SCNNode(); rim.light = Self.light(.directional, 600, color: UIColor(red: 0.8, green: 0.88, blue: 1, alpha: 1))
        rim.position = SCNVector3(4, 3, -6); rim.look(at: SCNVector3Zero); root.addChildNode(rim)
        let amb = SCNNode(); amb.light = Self.light(.ambient, 260, color: UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 1)); root.addChildNode(amb)

        // Base and glass.
        let base = SCNNode(geometry: SCNCylinder(radius: 0.95, height: 0.18))
        base.geometry?.materials = [Self.pbr(UIColor(hex: 0x2E3742), rough: 0.5, metal: 0.4)]
        base.position = SCNVector3(0, 0.09, 0); root.addChildNode(base)

        let glassGeo = SCNTube(innerRadius: 0.68, outerRadius: 0.72, height: Self.innerHeight + 0.15)
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 1, alpha: 0.12)
        glass.roughness.contents = 0.04
        glass.metalness.contents = 0.0
        glass.transparencyMode = .dualLayer
        glass.blendMode = .alpha
        glass.isDoubleSided = true
        glass.fresnelExponent = 2.2
        glass.reflective.contents = UIColor(white: 1, alpha: 0.6)
        glassGeo.materials = [glass]
        let glassNode = SCNNode(geometry: glassGeo)
        glassNode.position = SCNVector3(0, 0.18 + Float(Self.innerHeight + 0.15) / 2, 0)
        glassNode.renderingOrder = 10
        root.addChildNode(glassNode)

        // Scale marks every fifth of the height.
        for i in 1...4 {
            let mark = SCNNode(geometry: SCNBox(width: 0.22, height: 0.025, length: 0.02, chamferRadius: 0.01))
            mark.geometry?.materials = [Self.pbr(UIColor(white: 1, alpha: 0.85), rough: 0.4)]
            mark.position = SCNVector3(0.55, 0.2 + Float(Self.innerHeight) * Float(i) / 5, 0.45)
            mark.eulerAngles.y = -.pi / 4
            root.addChildNode(mark)
        }

        // Liquid: a cylinder that grows from the bottom, with a brighter surface disc on top.
        liquidMat.transparency = 0.82
        liquidMat.emission.contents = UIColor(hex: 0x0C3A7A)
        liquid.geometry = SCNCylinder(radius: 0.66, height: 0.01)
        liquid.geometry?.materials = [liquidMat]
        root.addChildNode(liquid)
        surface.geometry = SCNCylinder(radius: 0.66, height: 0.012)
        surface.geometry?.materials = [Self.pbr(UIColor(hex: 0xA8D8FF), rough: 0.05)]
        root.addChildNode(surface)
        let wobble = SCNAction.sequence([.rotateBy(x: 0.03, y: 0, z: 0.02, duration: 1.6), .rotateBy(x: -0.03, y: 0, z: -0.02, duration: 1.6)])
        wobble.timingMode = .easeInEaseOut
        surface.runAction(.repeatForever(wobble))

        // The cloud overhead.
        cloudMat.lightingModel = .physicallyBased
        cloudMat.roughness.contents = 1.0
        cloudMat.metalness.contents = 0.0
        cloudMat.diffuse.contents = UIColor(white: 0.93, alpha: 1)
        for (x, y, z, r) in [(-0.55, 0.0, 0.0, 0.55), (0.25, 0.15, 0.1, 0.7), (0.95, -0.05, -0.05, 0.48), (-0.05, -0.2, 0.35, 0.45), (0.5, -0.2, -0.35, 0.42)] as [(Float, Float, Float, CGFloat)] {
            let s = SCNNode(geometry: SCNSphere(radius: r)); s.geometry?.materials = [cloudMat]
            s.position = SCNVector3(x, y, z); cloud.addChildNode(s)
        }
        cloud.position = SCNVector3(-0.15, 3.3, 0)
        cloud.renderingOrder = 0
        let drift = SCNAction.sequence([.moveBy(x: 0.25, y: 0, z: 0, duration: 5), .moveBy(x: -0.25, y: 0, z: 0, duration: 5)])
        drift.timingMode = .easeInEaseOut
        cloud.runAction(.repeatForever(drift), forKey: "drift")
        root.addChildNode(cloud)
        cloud.addChildNode(precip)

        glint.light = Self.light(.omni, 0, color: UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1))
        glint.position = SCNVector3(1.2, 2.2, 1.6)
        root.addChildNode(glint)
        configure(level: 0, intensity: 0, snow: false)
    }

    /// level: 0…1 of the gauge; intensity: 0…1 of the falling rain or snow.
    func configure(level: Double, intensity: Double, snow: Bool) {
        let key = ((level * 50).rounded(), (intensity * 10).rounded(), snow)
        if let l = last, l == key { return }
        let first = last == nil
        last = key
        let h = max(0.01, CGFloat(min(1, max(0, level))) * Self.innerHeight)
        SCNTransaction.begin(); SCNTransaction.animationDuration = first ? 0 : 0.9
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        (liquid.geometry as? SCNCylinder)?.height = h
        liquid.position = SCNVector3(0, 0.18 + Float(h) / 2, 0)
        surface.position = SCNVector3(0, 0.18 + Float(h), 0)
        surface.opacity = level > 0.005 ? 1 : 0
        liquidMat.diffuse.contents = snow ? UIColor(white: 0.97, alpha: 1) : UIColor(hex: 0x3EA0FF)
        liquidMat.emission.contents = snow ? UIColor(white: 0.25, alpha: 1) : UIColor(hex: 0x0C3A7A)
        liquidMat.roughness.contents = snow ? 0.9 : 0.15
        // Rain: a full grey cloud. Dry: a small white fair-weather cloud. Always solid, never see-through.
        let wet = intensity > 0.02
        cloud.opacity = 1
        cloud.scale = wet ? SCNVector3(1, 1, 1) : SCNVector3(0.62, 0.62, 0.62)
        cloudMat.diffuse.contents = wet ? UIColor(white: 0.62 - 0.22 * CGFloat(min(1, intensity)), alpha: 1) : UIColor(white: 0.97, alpha: 1)
        glint.light?.intensity = intensity > 0.02 ? 0 : 900
        SCNTransaction.commit()

        precip.removeAllParticleSystems()
        animating = true
        guard intensity > 0.02 else { return }
        let ps = SCNParticleSystem()
        ps.particleImage = Self.dot
        ps.birthRate = CGFloat((snow ? 30 : 60) + intensity * (snow ? 90 : 260)) * (calm ? 0.3 : 1)
        ps.emitterShape = SCNBox(width: 1.6, height: 0.05, length: 0.8, chamferRadius: 0)
        ps.birthLocation = .volume
        ps.emittingDirection = SCNVector3(0, -1, 0)
        ps.spreadingAngle = snow ? 18 : 2
        ps.particleVelocity = snow ? 0.7 : 5.5
        ps.particleVelocityVariation = snow ? 0.3 : 1
        ps.particleLifeSpan = snow ? 4.2 : 0.65
        ps.particleSize = snow ? 0.05 : 0.022
        ps.stretchFactor = snow ? 0 : 0.06
        ps.particleColor = snow ? UIColor(white: 1, alpha: 0.95) : UIColor(red: 0.62, green: 0.82, blue: 1, alpha: 0.85)
        ps.isAffectedByGravity = false
        ps.blendMode = .alpha
        precip.position = SCNVector3(0.15, -0.35, 0)
        precip.addParticleSystem(ps)
    }

    override func calmChanged() { last = nil }
}

// MARK: - Sun: a floating island under the real sun, with a shadow that turns through the day

final class SunHero: HeroScene {
    private let sun = SCNNode()
    private let sunLight = SCNNode()
    private let moonNode = SCNNode()
    private let amb = SCNNode()
    private let grassMat = HeroScene.pbr(UIColor(hex: 0x6FAE5A), rough: 0.9)
    private let sunMat = SCNMaterial()
    private var last: (Double, Double)?
    static let radius: Float = 4.6

    init() {
        super.init(home: SCNVector3(0, 3.0, 9.5), target: SCNVector3(0, 0.6, 0))
        let root = scene.rootNode

        // Island: a grassy disc over a rocky cone.
        let top = SCNNode(geometry: SCNCylinder(radius: 2.1, height: 0.22))
        top.geometry?.materials = [grassMat]
        top.position = SCNVector3(0, -0.11, 0)
        root.addChildNode(top)
        let rock = SCNNode(geometry: SCNCone(topRadius: 2.1, bottomRadius: 0.25, height: 1.7))
        rock.geometry?.materials = [Self.pbr(UIColor(hex: 0x7A6450), rough: 1)]
        rock.position = SCNVector3(0, -1.07, 0)
        root.addChildNode(rock)

        // A tree and a small stone, both casting shadows.
        let trunk = SCNNode(geometry: SCNCylinder(radius: 0.08, height: 1.0))
        trunk.geometry?.materials = [Self.pbr(UIColor(hex: 0x6B4A2E), rough: 0.9)]
        trunk.position = SCNVector3(0.2, 0.5, -0.2)
        root.addChildNode(trunk)
        let leafMat = Self.pbr(UIColor(hex: 0x3F8F4A), rough: 0.85)
        for (x, y, z, r) in [(0.2, 1.25, -0.2, 0.5), (-0.1, 1.05, -0.05, 0.36), (0.5, 1.05, -0.1, 0.34), (0.25, 1.55, -0.25, 0.32)] as [(Float, Float, Float, CGFloat)] {
            let s = SCNNode(geometry: SCNSphere(radius: r)); s.geometry?.materials = [leafMat]
            s.position = SCNVector3(x, y, z); root.addChildNode(s)
        }
        let stone = SCNNode(geometry: SCNBox(width: 0.18, height: 0.5, length: 0.18, chamferRadius: 0.04))
        stone.geometry?.materials = [Self.pbr(UIColor(hex: 0xC9C2B4), rough: 0.7)]
        stone.position = SCNVector3(-0.9, 0.25, 0.6)
        root.addChildNode(stone)

        // Sunlight: a directional light from where the sun really is.
        let l = Self.light(.directional, 1300)
        l.castsShadow = true
        l.shadowMapSize = CGSize(width: 2048, height: 2048)
        l.shadowRadius = 3
        l.shadowSampleCount = 8
        l.shadowColor = UIColor(white: 0, alpha: 0.5)
        l.orthographicScale = 4
        l.automaticallyAdjustsShadowProjection = true
        sunLight.light = l
        root.addChildNode(sunLight)
        amb.light = Self.light(.ambient, 320, color: UIColor(red: 0.75, green: 0.82, blue: 0.95, alpha: 1))
        root.addChildNode(amb)

        // The sun itself, glowing.
        sunMat.lightingModel = .constant
        let ball = SCNSphere(radius: 0.32); ball.materials = [sunMat]
        sun.geometry = ball
        let glow = SCNNode(geometry: SCNPlane(width: 2.2, height: 2.2))
        let gm = SCNMaterial(); gm.lightingModel = .constant; gm.diffuse.contents = Self.halo
        gm.blendMode = .add; gm.writesToDepthBuffer = false
        glow.geometry?.materials = [gm]
        glow.constraints = [SCNBillboardConstraint()]
        glow.name = "glow"
        sun.addChildNode(glow)
        root.addChildNode(sun)

        let m = SCNSphere(radius: 0.2); m.materials = [{ let x = SCNMaterial(); x.lightingModel = .constant; x.diffuse.contents = UIColor(white: 0.92, alpha: 1); return x }()]
        moonNode.geometry = m
        root.addChildNode(moonNode)
    }

    /// Facing south: east on the left, west on the right, the sun's noon high and behind the island.
    static func spot(altitude: Double, azimuth: Double, radius: Float = radius) -> SCNVector3 {
        let alt = altitude * .pi / 180, az = azimuth * .pi / 180
        let r = Double(radius)
        return SCNVector3(Float(-r * cos(alt) * sin(az)), Float(r * sin(alt)) + 0.3, Float(r * cos(alt) * cos(az)))
    }

    func configure(sun s: (altitude: Double, azimuth: Double), rising: Bool, moon: (altitude: Double, azimuth: Double)?) {
        let key = ((s.altitude * 2).rounded(), (s.azimuth * 2).rounded())
        if let l = last, l == key { return }
        let first = last == nil
        last = key
        let up = s.altitude > -1
        SCNTransaction.begin(); SCNTransaction.animationDuration = first ? 0 : 0.5
        sun.position = Self.spot(altitude: max(s.altitude, -12), azimuth: s.azimuth)
        sun.opacity = up ? 1 : 0
        let color = WeatherScene.sunColor(altitude: max(s.altitude, 0), rising: rising)
        sunMat.diffuse.contents = color
        sun.childNode(withName: "glow", recursively: false)?.geometry?.firstMaterial?.multiply.contents = color
        if up {
            sunLight.position = Self.spot(altitude: max(s.altitude, 2), azimuth: s.azimuth, radius: 8)
            sunLight.look(at: SCNVector3Zero)
            sunLight.light?.color = color.blended(toward: .white, by: 0.55)
            let strength: Double = min(1, max(0, s.altitude / 30))
            let lux: Double = 500 + strength * 900
            sunLight.light?.intensity = CGFloat(lux)
            amb.light?.intensity = 320
            amb.light?.color = UIColor(red: 0.78, green: 0.85, blue: 0.98, alpha: 1)
            grassMat.diffuse.contents = UIColor(hex: 0x6FAE5A)
        } else if let m = moon, m.altitude > 0 {
            sunLight.position = Self.spot(altitude: max(m.altitude, 5), azimuth: m.azimuth, radius: 8)
            sunLight.look(at: SCNVector3Zero)
            sunLight.light?.color = UIColor(red: 0.7, green: 0.8, blue: 1, alpha: 1)
            sunLight.light?.intensity = 260
            amb.light?.intensity = 140
            amb.light?.color = UIColor(red: 0.45, green: 0.55, blue: 0.85, alpha: 1)
            grassMat.diffuse.contents = UIColor(hex: 0x3A5E48)
        } else {
            sunLight.light?.intensity = 0
            amb.light?.intensity = 180
            amb.light?.color = UIColor(red: 0.4, green: 0.5, blue: 0.8, alpha: 1)
            grassMat.diffuse.contents = UIColor(hex: 0x3A5E48)
        }
        if let m = moon, m.altitude > -2, !up {
            moonNode.position = Self.spot(altitude: m.altitude, azimuth: m.azimuth)
            moonNode.opacity = 1
        } else {
            moonNode.opacity = 0
        }
        SCNTransaction.commit()
    }
}

// MARK: - Air: a windsock over a compass, with air streaming past

final class AirHero: HeroScene {
    private let pivot = SCNNode()
    private let droop = SCNNode()
    private let sock = SCNNode()
    private let streaks = SCNNode()
    private var last: (Double, Double, Int)?

    init() {
        super.init(home: SCNVector3(0, 3.2, 8.6), target: SCNVector3(0, 1.0, 0))
        let root = scene.rootNode
        let key = SCNNode(); key.light = Self.light(.directional, 1150)
        key.light?.castsShadow = true; key.light?.shadowRadius = 3; key.light?.shadowColor = UIColor(white: 0, alpha: 0.35)
        key.position = SCNVector3(-4, 8, 4); key.look(at: SCNVector3Zero); root.addChildNode(key)
        let amb = SCNNode(); amb.light = Self.light(.ambient, 300, color: UIColor(red: 0.78, green: 0.84, blue: 0.96, alpha: 1)); root.addChildNode(amb)

        // Compass disc with N E S W (map view: north away from you, east to the right).
        let disc = SCNNode(geometry: SCNCylinder(radius: 2.0, height: 0.08))
        disc.geometry?.materials = [Self.pbr(UIColor(hex: 0x2F3A46), rough: 0.6, metal: 0.2)]
        disc.position = SCNVector3(0, -0.04, 0)
        root.addChildNode(disc)
        let ring = SCNNode(geometry: SCNTorus(ringRadius: 1.85, pipeRadius: 0.025))
        ring.geometry?.materials = [Self.pbr(UIColor(white: 0.9, alpha: 1), rough: 0.3, metal: 0.6)]
        ring.position = SCNVector3(0, 0.01, 0)
        root.addChildNode(ring)
        for (label, x, z) in [("N", Float(0), Float(-1.55)), ("S", 0, 1.55), ("E", 1.55, 0), ("W", -1.55, 0)] {
            let t = SCNText(string: label, extrusionDepth: 0.02)
            t.font = UIFont.systemFont(ofSize: 12, weight: .heavy)
            t.flatness = 0.2
            t.materials = [Self.pbr(label == "N" ? UIColor(hex: 0xFF6B3D) : UIColor(white: 0.95, alpha: 1), rough: 0.5)]
            let n = SCNNode(geometry: t)
            let (mn, mx) = t.boundingBox
            n.pivot = SCNMatrix4MakeTranslation((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, 0)
            n.eulerAngles.x = -.pi / 2
            n.scale = SCNVector3(0.035, 0.035, 0.035)
            n.position = SCNVector3(x, 0.03, z)
            root.addChildNode(n)
        }

        // Pole.
        let pole = SCNNode(geometry: SCNCylinder(radius: 0.045, height: 2.4))
        pole.geometry?.materials = [Self.pbr(UIColor(white: 0.85, alpha: 1), rough: 0.3, metal: 0.8)]
        pole.position = SCNVector3(0, 1.2, 0)
        root.addChildNode(pole)

        // Sock: a striped cone hanging from a pivot at the top of the pole.
        let cone = SCNCone(topRadius: 0.12, bottomRadius: 0.3, height: 1.5)
        let stripes = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 100)).image { ctx in
            for i in 0..<5 {
                (i % 2 == 0 ? UIColor(hex: 0xFF6B3D) : UIColor.white).setFill()
                ctx.fill(CGRect(x: 0, y: CGFloat(i) * 20, width: 8, height: 20))
            }
        }
        let sm = Self.pbr(.white, rough: 0.7)
        sm.diffuse.contents = stripes
        sm.isDoubleSided = true
        cone.materials = [sm]
        sock.geometry = cone
        // The cone's wide mouth sits at the pole and its narrow tail points along +x (downwind).
        sock.eulerAngles.z = -.pi / 2
        sock.position = SCNVector3(0.75, 0, 0)
        droop.addChildNode(sock)
        pivot.addChildNode(droop)
        pivot.position = SCNVector3(0, 2.3, 0)
        root.addChildNode(pivot)
        root.addChildNode(streaks)
    }

    /// speed in km/h; from = the direction the wind comes FROM; aqi tints the haze.
    func configure(speedKmh: Double, from: Double, aqi: Int?) {
        let key = ((speedKmh / 2).rounded(), (from / 10).rounded(), (aqi ?? 0) / 25)
        if let l = last, l == key { return }
        let first = last == nil
        last = key
        let toward = (from + 180) * .pi / 180
        let strength = min(1, max(0, speedKmh / 45))
        // Yaw points the sock downwind; droop goes from hanging (calm) to straight out (strong).
        let yaw = Float(-(toward - .pi / 2))
        let droop = Float(-(1 - strength) * 1.25)
        SCNTransaction.begin(); SCNTransaction.animationDuration = first ? 0 : 0.8
        pivot.eulerAngles = SCNVector3(0, yaw, 0)
        self.droop.eulerAngles = SCNVector3(0, 0, droop)
        SCNTransaction.commit()

        sock.removeAction(forKey: "flutter")
        if !calm && speedKmh > 3 {
            let a = CGFloat(0.04 + strength * 0.1), t = 0.35 - strength * 0.2
            let flutter = SCNAction.sequence([.rotateBy(x: a, y: a * 0.5, z: 0, duration: t), .rotateBy(x: -a, y: -a * 0.5, z: 0, duration: t)])
            sock.runAction(.repeatForever(flutter), forKey: "flutter")
        }

        // Streaks flowing downwind, faster and denser with more wind.
        streaks.removeAllParticleSystems()
        let dx = Float(sin(toward)), dz = Float(-cos(toward))
        if speedKmh > 2 {
            let ps = SCNParticleSystem()
            ps.particleImage = Self.dot
            ps.birthRate = CGFloat(20 + strength * 140) * (calm ? 0.3 : 1)
            ps.emitterShape = SCNBox(width: 0.05, height: 2.2, length: 3.6, chamferRadius: 0)
            ps.birthLocation = .volume
            ps.emittingDirection = SCNVector3(1, 0, 0)
            ps.spreadingAngle = 3
            ps.particleVelocity = CGFloat(1.2 + strength * 5)
            ps.particleLifeSpan = CGFloat(4.2 / (1.2 + strength * 5) * 1.4)
            ps.particleSize = 0.03
            ps.stretchFactor = CGFloat(0.05 + strength * 0.12)
            ps.particleColor = UIColor(white: 1, alpha: 0.55)
            ps.blendMode = .additive
            streaks.addParticleSystem(ps)
        }
        // The emitter sits upwind and points along the wind.
        streaks.position = SCNVector3(-dx * 2.4, 1.3, -dz * 2.4)
        streaks.eulerAngles = SCNVector3(0, Float(atan2(-Double(dz), Double(dx))), 0)

        // Haze tinted by the air-quality category.
        if let aqi, aqi > 50 {
            scene.fogColor = UIColor(hex: Verdicts.aqiHex(aqi)).withAlphaComponent(1)
            scene.fogStartDistance = 5
            scene.fogEndDistance = CGFloat(max(9, 22 - Double(aqi) / 12))
            scene.fogDensityExponent = 1.4
        } else {
            scene.fogEndDistance = 0
            scene.fogStartDistance = 0
        }
        animating = true
    }

    override func calmChanged() { last = nil }
}
