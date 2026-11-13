import AVFoundation
import UIKit

/// Procedural weather sound: rain hiss, wind, and thunder rumbles, synthesized live (no audio files).
/// Uses the .ambient audio category, so the phone's silent switch mutes it and it mixes with your music.
final class SoundEngine {
    static let shared = SoundEngine()

    var enabled = true { didSet { refresh() } }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private var running = false

    // Targets set from the UI; smoothed on the audio thread.
    private var rainTarget: Float = 0
    private var windTarget: Float = 0
    private var rain: Float = 0
    private var wind: Float = 0
    private var thunderEnv: Float = 0
    private var rumbleSeed: Float = 0

    // Filter state
    private var lpRain: Float = 0
    private var lpWind: Float = 0
    private var lpWind2: Float = 0
    private var lpThunder: Float = 0
    private var lpThunder2: Float = 0
    private var phase: Float = 0
    private var seed: UInt32 = 22_222
    private var sampleRate: Float = 48_000

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        let rate = AVAudioSession.sharedInstance().sampleRate > 0 ? AVAudioSession.sharedInstance().sampleRate : 48_000
        sampleRate = Float(rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let node = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, abl -> OSStatus in
            self.render(frameCount: Int(frameCount), abl: abl)
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.55
    }

    /// rain, wind: 0…1
    func set(rain: Double, wind: Double) {
        rainTarget = Float(min(1, max(0, rain)))
        windTarget = Float(min(1, max(0, wind)))
        refresh()
    }

    func thunder() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.9)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
        }
        guard enabled else { return }
        thunderEnv = 1
        rumbleSeed = Float.random(in: 0.6...1)
        refresh(force: true)
    }

    func stop() {
        rainTarget = 0; windTarget = 0
        if running { engine.pause(); running = false }
    }

    private func refresh(force: Bool = false) {
        let wantsSound = enabled && (rainTarget > 0.01 || windTarget > 0.01 || force)
        if wantsSound && !running {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try engine.start()
                running = true
            } catch { running = false }
        } else if !wantsSound && running && thunderEnv < 0.01 {
            // Let the levels fade out, then pause to save battery.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.rainTarget <= 0.01, self.windTarget <= 0.01, self.thunderEnv < 0.01 else { return }
                self.engine.pause(); self.running = false
            }
        }
    }

    @inline(__always) private func noise() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    private func render(frameCount: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let smooth: Float = 0.00008
        let twoPi = Float.pi * 2
        for f in 0..<frameCount {
            rain += (rainTarget - rain) * smooth
            wind += (windTarget - wind) * smooth

            let n = noise()
            // Rain: bright hiss with a little crackle.
            lpRain += (n - lpRain) * 0.35
            var r = (n - lpRain) * 0.5
            if noise() > 0.9993 { r += noise() * 0.6 }            // the odd heavy drop
            r *= rain * 0.55

            // Wind: deep filtered noise with slow gusting.
            lpWind += (n - lpWind) * 0.012
            lpWind2 += (lpWind - lpWind2) * 0.02
            phase += 0.13 / sampleRate
            if phase > 1 { phase -= 1 }
            let gust = 0.55 + 0.45 * sin(phase * twoPi) * sin(phase * twoPi * 0.37 + 1)
            let w = lpWind2 * wind * 9 * gust

            // Thunder: very low rumble that decays over ~2 seconds.
            lpThunder += (n - lpThunder) * 0.004
            lpThunder2 += (lpThunder - lpThunder2) * 0.006
            let t = lpThunder2 * thunderEnv * 26 * rumbleSeed
            thunderEnv *= 0.99997

            let s = max(-0.95, min(0.95, r + w + t))
            for b in buffers {
                b.mData?.assumingMemoryBound(to: Float.self)[f] = s
            }
        }
    }
}
