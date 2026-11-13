import SwiftUI
import SceneKit

/// Tonight's moon as a real 3D sphere you can spin — maria, craters and the phase's terminator.
struct MoonOrbView: UIViewRepresentable {
    let age: Double
    let tint: UInt32

    final class Coordinator { var material = SCNMaterial(); var node = SCNNode() }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let cam = SCNNode(); cam.camera = SCNCamera()
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
        scene.rootNode.addChildNode(n)
        // A slow sway so it reads as a ball, not a sticker.
        let sway = SCNAction.sequence([.rotateBy(x: 0, y: 0.22, z: 0, duration: 9), .rotateBy(x: 0, y: -0.22, z: 0, duration: 9)])
        sway.timingMode = .easeInEaseOut
        n.runAction(.repeatForever(sway))

        v.scene = scene
        v.pointOfView = cam
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        v.cameraControlConfiguration.allowsTranslation = false
        v.isPlaying = true
        update(m)
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) { update(context.coordinator.material) }

    private func update(_ m: SCNMaterial) {
        MoonLook.setAge(age, on: m)
        MoonLook.setTint(UIColor(hex: tint), on: m)
    }
}
