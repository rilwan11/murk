import SwiftUI
import SceneKit

/// Tonight's moon as a real 3D sphere you can spin — maria, craters and the phase's terminator.
struct MoonOrbView: UIViewRepresentable {
    let age: Double
    let tint: UInt32
    /// The sky behind the moon when it's daytime (nil at night).
    var daySky: UInt32? = nil
    var active = true
    var calm = false
    /// Change it to put the camera back where it started.
    var resetToken = 0

    final class Coordinator {
        var material = SCNMaterial(); var node = SCNNode(); let tilt = SCNNode()
        var camera = SCNNode(); weak var view: SCNView?; var resetToken = 0
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let cam = context.coordinator.camera; cam.camera = SCNCamera()
        cam.camera?.fieldOfView = 30
        cam.position = SCNVector3(0, 0, 4.3)
        scene.rootNode.addChildNode(cam)

        let m = context.coordinator.material
        MoonLook.configure(m)
        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 128
        sphere.materials = [m]
        let n = context.coordinator.node
        n.geometry = sphere
        n.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)    // near side toward us
        context.coordinator.tilt.addChildNode(n)
        scene.rootNode.addChildNode(context.coordinator.tilt)
        // A slow sway so it reads as a ball, not a sticker.
        let sway = SCNAction.sequence([.rotateBy(x: 0, y: 0.22, z: 0, duration: 9), .rotateBy(x: 0, y: -0.22, z: 0, duration: 9)])
        sway.timingMode = .easeInEaseOut
        if !calm { n.runAction(.repeatForever(sway)) }

        v.scene = scene
        v.pointOfView = cam
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.cameraControlConfiguration.allowsTranslation = false
        v.isPlaying = active
        v.rendersContinuously = false
        context.coordinator.view = v
        context.coordinator.resetToken = resetToken
        update(m)
        MotionTilt.shared.follow(context.coordinator.tilt, owner: context.coordinator, on: active && !calm)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        let c = context.coordinator
        update(c.material)
        v.scene?.isPaused = !active
        v.isPlaying = active
        MotionTilt.shared.follow(c.tilt, owner: c, on: active && !calm)
        if c.resetToken != resetToken {
            c.resetToken = resetToken
            v.defaultCameraController.stopInertia()
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            for n in [c.camera, v.pointOfView].compactMap({ $0 }) {
                n.position = SCNVector3(0, 0, 4.3)
                n.orientation = SCNQuaternion(0, 0, 0, 1)
            }
            SCNTransaction.completionBlock = { v.pointOfView = c.camera }
            SCNTransaction.commit()
        }
    }

    static func dismantleUIView(_ v: SCNView, coordinator: Coordinator) {
        MotionTilt.shared.remove(coordinator)
    }

    private func update(_ m: SCNMaterial) {
        MoonLook.setAge(age, on: m)
        MoonLook.setTint(UIColor(hex: tint), on: m)
        MoonLook.setDaySky(daySky.map { UIColor(hex: $0) }, on: m)
    }
}
