// AlarmSound.swift
// Alarm-clock sounds for reminders: a pattern that repeats until the alarm is stopped,
// starting softer and getting louder (like a real alarm clock).

import AppKit

enum AlarmSound {

    static let defaultName = "따르릉"

    /// Synthesized alarm patterns, in picker order.
    static let builtIn = ["따르릉", "삐삐삐삐", "딩동댕", "뽀잉뽀잉"]
    /// macOS system sounds and the user's own files (CustomSounds) can be looped as alarms too.
    static var system: [String] { PetSound.system }

    private static var cache: [String: Data] = [:]

    /// One period of the pattern, including the pause before it repeats.
    static func makeSound(_ name: String) -> NSSound? {
        if CustomSounds.isCustom(name) {
            // File deleted → still ring, with the default alarm.
            return CustomSounds.shared.makeSound(name) ?? makeSound(defaultName)
        }
        guard builtIn.contains(name) else { return NSSound(named: NSSound.Name(name)) }
        if cache[name] == nil { cache[name] = synthesize(name) }
        return cache[name].flatMap { NSSound(data: $0) }
    }

    /// Seconds between repeats.
    static func period(of name: String) -> TimeInterval {
        let duration = makeSound(name)?.duration ?? 1
        return builtIn.contains(name) ? duration : max(duration + 0.35, 1)
    }

    /// Play one period (settings preview). Long custom files are cut off after a few seconds.
    private static var preview: NSSound?
    static func playPreview(_ name: String, volume: Double) {
        preview?.stop()
        let sound = makeSound(name)
        preview = sound
        sound?.volume = Float(volume)
        sound?.play()
        if let sound, sound.duration > previewLimit {
            DispatchQueue.main.asyncAfter(deadline: .now() + previewLimit) { [weak sound] in sound?.stop() }
        }
    }

    static let previewLimit: TimeInterval = 8

    // MARK: - Synthesis

    private static func synthesize(_ name: String) -> Data {
        switch name {
        case "따르릉":
            // Classic bell: fast trill between two pitches, then a short pause.
            let ring = 0.9
            return PetSound.wav(duration: 1.35,
                                frequency: { t in Int(t / 0.035) % 2 == 0 ? 1250 : 1580 },
                                envelope: { t in t < ring ? PetSound.attack(t) * min((ring - t) / 0.02, 1) : 0 },
                                overtone: 0.35)
        case "삐삐삐삐":
            // Digital clock: four short beeps.
            let beep = 0.09, gap = 0.07
            return PetSound.wav(duration: 1.1,
                                frequency: { _ in 2093 },
                                envelope: { t in
                                    let slot = t / (beep + gap)
                                    let local = (slot - slot.rounded(.down)) * (beep + gap)
                                    return slot < 4 && local < beep ? min(local / 0.004, (beep - local) / 0.004, 1) : 0
                                })
        case "딩동댕":
            // Cheerful arpeggio C6 E6 G6 C7.
            let notes: [Double] = [1046.5, 1318.5, 1568, 2093]
            let step = 0.16
            return PetSound.wav(duration: 1.4,
                                frequency: { t in notes[min(Int(t / step), notes.count - 1)] },
                                envelope: { t in
                                    guard t < step * Double(notes.count) else { return 0 }
                                    let local = t.truncatingRemainder(dividingBy: step)
                                    return PetSound.attack(local) * exp(-local * 9)
                                },
                                overtone: 0.2)
        default: // "뽀잉뽀잉"
            let boing = 0.32
            return PetSound.wav(duration: 1.2,
                                frequency: { t in
                                    let local = t.truncatingRemainder(dividingBy: boing)
                                    return 250 + 650 * exp(-local * 4) + 45 * sin(2 * .pi * 17 * local)
                                },
                                envelope: { t in
                                    guard t < boing * 2 else { return 0 }
                                    let local = t.truncatingRemainder(dividingBy: boing)
                                    return PetSound.attack(local) * exp(-local * 7)
                                })
        }
    }
}

/// Plays an alarm sound on repeat until stopped, ramping the volume up over the first seconds.
final class AlarmPlayer {

    private enum Constants {
        static let startVolumeRatio = 0.35
        static let rampDuration: TimeInterval = 20
    }

    private let soundName: String
    private let volume: Double
    private var timer: Timer?
    private var current: NSSound?
    private var startedAt = Date()

    init(soundName: String, volume: Double) {
        self.soundName = soundName
        self.volume = min(max(volume, 0.05), 1)
    }

    var isPlaying: Bool { timer != nil }

    func start() {
        stop()
        startedAt = Date()
        playOnce()
        timer = Timer.scheduledTimer(withTimeInterval: AlarmSound.period(of: soundName), repeats: true) { [weak self] _ in
            self?.playOnce()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current?.stop()
        current = nil
    }

    private func playOnce() {
        let ramp = min(Date().timeIntervalSince(startedAt) / Constants.rampDuration, 1)
        let level = volume * (Constants.startVolumeRatio + (1 - Constants.startVolumeRatio) * ramp)
        current?.stop()
        current = AlarmSound.makeSound(soundName)
        current?.volume = Float(level)
        current?.play()
    }
}
