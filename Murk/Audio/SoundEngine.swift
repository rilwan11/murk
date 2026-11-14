import AVFoundation
import UIKit

/// Procedural weather sound: rain hiss, wind, and thunder rumbles, synthesized live (no audio files).
/// Uses the .ambient audio category, so the phone's silent switch mutes it and it mixes with your music.
///
/// Threading: the UI talks to the audio thread only through `MurkSoundControl` (C atomics).
/// All filter and envelope state lives in `DSP`, which only the audio thread touches. The render
/// callback takes no locks, allocates nothing, and never touches this object.
final class SoundEngine {
    static let shared = SoundEngine()

    /// Main thread only.
    var enabled = true { didSet { refresh() } }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var running = false
    private var suspended = false
    private var rainTarget: Float = 0
    private var windTarget: Float = 0
    private var observers: [NSObjectProtocol] = []

    private let control: OpaquePointer = MurkSoundControlCreate()
    private let dsp: UnsafeMutablePointer<DSP> = {
        let p = UnsafeMutablePointer<DSP>.allocate(capacity: 1)
        p.initialize(to: DSP())
        return p
    }()

    /// Owned by the audio thread.
    private struct DSP {
        var rain: Float = 0
        var wind: Float = 0
        var thunderEnv: Float = 0
        var rumble: Float = 0
        var thunderSerial: UInt32 = 0
        var lpRain: Float = 0
        var lpWind: Float = 0
        var lpWind2: Float = 0
        var lpThunder: Float = 0
        var lpThunder2: Float = 0
        var phase: Float = 0
        var seed: UInt32 = 22_222
    }

    private init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        buildGraph()

        let nc = NotificationCenter.default
        // The output route changed (headphones, Bluetooth, CarPlay): the engine stops itself and must be rewired.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            self.running = false
            if type == .ended { self.refresh() }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            self.handleConfigurationChange()
        })
    }

    private func outputRate() -> Double {
        let hw = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if hw > 0 { return hw }
        let s = AVAudioSession.sharedInstance().sampleRate
        return s > 0 ? s : 48_000
    }

    private func buildGraph() {
        let rate = outputRate()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        MurkSoundControlSetSampleRate(control, Float(rate))
        if let old = source { engine.disconnectNodeOutput(old); engine.detach(old) }
        let control = self.control, dsp = self.dsp
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, abl -> OSStatus in
            SoundEngine.render(dsp, control, frames: Int(frameCount), abl: abl)
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
    }

    private func handleConfigurationChange() {
        running = false
        buildGraph()
        refresh()
    }

    // MARK: Control (any thread; work hops to the main thread)

    /// rain, wind: 0…1
    func set(rain: Double, wind: Double) {
        onMain {
            self.rainTarget = Float(min(1, max(0, rain)))
            self.windTarget = Float(min(1, max(0, wind)))
            self.pushTargets()
            self.refresh()
        }
    }

    func thunder() {
        onMain {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
            }
            guard self.enabled, !self.suspended else { return }
            MurkSoundControlTriggerThunder(self.control, Float.random(in: 0.6...1))
            self.refresh(force: true)
            // Once the rumble has died away, let the engine pause again.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.refresh() }
        }
    }

    /// Silences everything and releases the audio hardware (app went to the background).
    func stop() {
        onMain {
            self.suspended = true
            MurkSoundControlSetTargets(self.control, 0, 0)
            MurkSoundControlPublishThunderLevel(self.control, 0)
            if self.running { self.engine.pause(); self.running = false }
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    /// Called when the app is active again; sound resumes with the last levels.
    func resume() {
        onMain {
            self.suspended = false
            self.pushTargets()
            self.refresh()
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func pushTargets() {
        let on = enabled && !suspended
        MurkSoundControlSetTargets(control, on ? rainTarget : 0, on ? windTarget : 0)
    }

    private func refresh(force: Bool = false, attempt: Int = 0) {
        pushTargets()
        let thunderLive = MurkSoundControlThunderLevel(control) > 0.01
        let wantsSound = enabled && !suspended && (rainTarget > 0.01 || windTarget > 0.01 || force || thunderLive)
        if wantsSound && !running {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                running = true
            } catch {
                running = false
                // The hardware can be briefly unavailable right after a route change; try once more.
                if attempt < 2 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                        guard let self, !self.running else { return }
                        if attempt == 1 { self.buildGraph() }
                        self.refresh(force: force, attempt: attempt + 1)
                    }
                }
            }
        } else if !wantsSound && running {
            // Let the levels fade out, then pause to save battery.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.running else { return }
                let quiet = !self.enabled || self.suspended || (self.rainTarget <= 0.01 && self.windTarget <= 0.01)
                guard quiet, MurkSoundControlThunderLevel(self.control) <= 0.01 else { return }
                self.engine.pause(); self.running = false
            }
        }
    }

    // MARK: Audio thread

    @inline(__always) private static func noise(_ seed: inout UInt32) -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    private static func render(_ state: UnsafeMutablePointer<DSP>, _ control: OpaquePointer, frames: Int,
                               abl: UnsafeMutablePointer<AudioBufferList>) {
        var d = state.pointee
        let rainTarget = MurkSoundControlRain(control)
        let windTarget = MurkSoundControlWind(control)
        let sampleRate = max(8_000, MurkSoundControlSampleRate(control))
        let serial = MurkSoundControlThunderSerial(control)
        if serial != d.thunderSerial {
            d.thunderSerial = serial
            d.thunderEnv = 1
            d.rumble = MurkSoundControlThunderStrength(control)
        }

        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let smooth: Float = 0.00008
        let twoPi = Float.pi * 2
        for f in 0..<frames {
            d.rain += (rainTarget - d.rain) * smooth
            d.wind += (windTarget - d.wind) * smooth

            let n = noise(&d.seed)
            // Rain: bright hiss with a little crackle.
            d.lpRain += (n - d.lpRain) * 0.35
            var r = (n - d.lpRain) * 0.5
            if noise(&d.seed) > 0.9993 { r += noise(&d.seed) * 0.6 }            // the odd heavy drop
            r *= d.rain * 0.55

            // Wind: deep filtered noise with slow gusting.
            d.lpWind += (n - d.lpWind) * 0.012
            d.lpWind2 += (d.lpWind - d.lpWind2) * 0.02
            d.phase += 0.13 / sampleRate
            if d.phase > 1 { d.phase -= 1 }
            let gust = 0.55 + 0.45 * sin(d.phase * twoPi) * sin(d.phase * twoPi * 0.37 + 1)
            let w = d.lpWind2 * d.wind * 9 * gust

            // Thunder: very low rumble that decays over ~2 seconds.
            d.lpThunder += (n - d.lpThunder) * 0.004
            d.lpThunder2 += (d.lpThunder - d.lpThunder2) * 0.006
            let t = d.lpThunder2 * d.thunderEnv * 26 * d.rumble
            d.thunderEnv *= 0.99997

            let s = max(-0.95, min(0.95, r + w + t))
            for b in buffers {
                b.mData?.assumingMemoryBound(to: Float.self)[f] = s
            }
        }
        state.pointee = d
        MurkSoundControlPublishThunderLevel(control, d.thunderEnv)
    }
}
