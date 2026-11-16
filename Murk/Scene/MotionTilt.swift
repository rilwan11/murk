import CoreMotion
import SceneKit
import UIKit

/// Tilting the phone tilts the 3D scenes a little, like looking into a diorama.
/// One motion manager for the whole app; it runs only while a visible scene is listening.
final class MotionTilt {
    static let shared = MotionTilt()
    static let settingKey = "tiltWithPhone"

    /// Off in Settings, or Reduce Motion is on.
    static var enabled: Bool {
        (UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true) && !UIAccessibility.isReduceMotionEnabled
    }

    /// Most the scene turns, in radians (about 9°).
    static let maxAngle: Float = 0.16

    private let manager = CMMotionManager()
    private var listeners: [ObjectIdentifier: (Float, Float) -> Void] = [:]
    private var base: (pitch: Double, roll: Double)?
    private var x: Double = 0, y: Double = 0

    /// `apply` gets (around x, around y) in radians, about 60 times a second, on the main thread.
    func add(_ owner: AnyObject, _ apply: @escaping (Float, Float) -> Void) {
        listeners[ObjectIdentifier(owner)] = apply
        start()
    }

    func remove(_ owner: AnyObject) {
        listeners[ObjectIdentifier(owner)] = nil
        if listeners.isEmpty { stop() }
    }

    private func start() {
        guard !manager.isDeviceMotionActive, manager.isDeviceMotionAvailable else { return }
        base = nil
        manager.deviceMotionUpdateInterval = 1.0 / 60
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let a = m?.attitude else { return }
            self.step(pitch: a.pitch, roll: a.roll)
        }
    }

    private func stop() {
        manager.stopDeviceMotionUpdates()
        x = 0; y = 0
    }

    /// Measured from a slowly drifting rest position, so however you hold the phone is "level"
    /// and only the tilt you add moves the scene; it eases back when you hold still.
    private func step(pitch: Double, roll: Double) {
        guard var b = base else { base = (pitch, roll); return }
        b.pitch += (pitch - b.pitch) * 0.012
        b.roll += (roll - b.roll) * 0.012
        base = b
        let limit = Double(Self.maxAngle)
        let tx = max(-limit, min(limit, (pitch - b.pitch) * 0.6))
        let ty = max(-limit, min(limit, (roll - b.roll) * 0.6))
        x += (tx - x) * 0.18
        y += (ty - y) * 0.18
        for apply in listeners.values { apply(Float(x), Float(y)) }
    }

    /// Follows the phone with `node` while `on`, or eases it back to level.
    func follow(_ node: SCNNode, owner: AnyObject, on: Bool) {
        if on && Self.enabled {
            add(owner) { [weak node] x, y in node?.eulerAngles = SCNVector3(x, y, 0) }
        } else {
            remove(owner)
            if node.eulerAngles.x != 0 || node.eulerAngles.y != 0 {
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.4
                node.eulerAngles = SCNVector3Zero
                SCNTransaction.commit()
            }
        }
    }
}
