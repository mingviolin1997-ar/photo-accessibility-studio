import AVFoundation
import Foundation

@MainActor
final class ProgressSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100,
                                       channels: 1)!
    private var timer: Timer?
    private var progress = 0.0
    private var playedHalfwayCue = false
    private var enabled = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start(enabled: Bool) {
        stop()
        self.enabled = enabled
        guard enabled, startEngineIfNeeded() else { return }
        progress = 0
        playedHalfwayCue = false
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.playProgressTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func update(progress newValue: Double) {
        let clamped = min(max(newValue, 0), 1)
        let crossedHalfway = progress < 0.5 && clamped >= 0.5
        progress = clamped
        if enabled, crossedHalfway, !playedHalfwayCue {
            playedHalfwayCue = true
            playSequence([(520, 0.09), (760, 0.13)], volume: 0.11)
        }
    }

    func complete() {
        timer?.invalidate()
        timer = nil
        progress = 1
        guard enabled, startEngineIfNeeded() else { return }
        playSequence([(660, 0.09), (880, 0.09), (1_180, 0.18)], volume: 0.13)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player.stop()
        enabled = false
        progress = 0
        playedHalfwayCue = false
    }

    private func playProgressTick() {
        guard enabled, startEngineIfNeeded() else { return }
        let frequency = 330 + (progress * 770)
        playSequence([(frequency, 0.075)], volume: 0.075)
    }

    private func startEngineIfNeeded() -> Bool {
        if !engine.isRunning {
            do {
                engine.prepare()
                try engine.start()
            } catch {
                AppLogger.shared.log("无法播放进度声音：\(error.localizedDescription)")
                return false
            }
        }
        if !player.isPlaying { player.play() }
        return true
    }

    private func playSequence(_ tones: [(frequency: Double, duration: Double)],
                              volume: Float) {
        guard startEngineIfNeeded() else { return }
        for tone in tones {
            guard let buffer = makeTone(frequency: tone.frequency,
                                        duration: tone.duration,
                                        volume: volume) else { continue }
            player.scheduleBuffer(buffer)
        }
    }

    private func makeTone(frequency: Double,
                          duration: Double,
                          volume: Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: frameCount),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let position = Double(frame) / Double(frameCount)
            let envelope = min(min(position / 0.12, (1 - position) / 0.18), 1)
            let angle = 2 * Double.pi * frequency * Double(frame) / sampleRate
            samples[frame] = Float(sin(angle)) * volume * Float(max(envelope, 0))
        }
        return buffer
    }
}
