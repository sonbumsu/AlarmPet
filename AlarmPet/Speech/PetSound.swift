// PetSound.swift
// Cute "the pet is talking" sound effects.
// Built-in sounds are synthesized in code (no audio files to ship);
// macOS system sounds (/System/Library/Sounds) can be picked too.

import AppKit

enum PetSound {

    /// Synthesized sounds, in picker order.
    static let builtIn = ["뿅", "삐롱", "뽀잉"]

    /// macOS system sounds available on this Mac (Pop, Purr, Tink, …).
    static let system: [String] = {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }()

    private static var cache: [String: Data] = [:]
    /// NSSound stops when deallocated, so keep the one that is playing.
    private static var playing: NSSound?

    static func play(_ name: String, volume: Double) {
        guard !name.isEmpty, let sound = makeSound(name) else { return }
        playing?.stop()
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
        playing = sound
    }

    private static func makeSound(_ name: String) -> NSSound? {
        guard builtIn.contains(name) else { return NSSound(named: NSSound.Name(name)) }
        if cache[name] == nil { cache[name] = synthesize(name) }
        return cache[name].flatMap { NSSound(data: $0) }
    }

    // MARK: - Synthesis

    private static func synthesize(_ name: String) -> Data {
        switch name {
        case "뿅":
            // Quick rising chirp.
            return wav(duration: 0.16,
                       frequency: { t in 500 * pow(3.2, t / 0.16) },
                       envelope: { t in attack(t) * exp(-t * 16) })
        case "삐롱":
            // Two bright notes, E6 → A6.
            let split = 0.09
            return wav(duration: 0.26,
                       frequency: { t in t < split ? 1318.5 : 1760 },
                       envelope: { t in
                           let local = t < split ? t : t - split
                           return attack(local) * exp(-local * (t < split ? 20 : 13))
                       },
                       overtone: 0.25)
        default: // "뽀잉"
            // Springy boing: falling pitch with a fast wobble.
            return wav(duration: 0.36,
                       frequency: { t in 250 + 650 * exp(-t * 4) + 45 * sin(2 * .pi * 17 * t) },
                       envelope: { t in attack(t) * exp(-t * 7) })
        }
    }

    /// 5 ms fade-in so the start doesn't click.
    static func attack(_ t: Double) -> Double { min(t / 0.005, 1) }

    /// 16-bit mono PCM WAV. Phase is integrated so pitch sweeps stay smooth.
    static func wav(duration: Double,
                            frequency: (Double) -> Double,
                            envelope: (Double) -> Double,
                            overtone: Double = 0) -> Data {
        let sampleRate = 44_100.0
        let count = Int(duration * sampleRate)
        var samples = [Int16](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / sampleRate
            phase += 2 * .pi * frequency(t) / sampleRate
            let value = (sin(phase) + overtone * sin(2 * phase)) / (1 + overtone) * envelope(t)
            samples[i] = Int16(max(-1, min(1, value)) * 0.8 * Double(Int16.max))
        }

        let dataSize = UInt32(count * 2)
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); append(36 + dataSize)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)); append(UInt16(1))                         // PCM, mono
        append(UInt32(sampleRate)); append(UInt32(sampleRate) * 2)  // sample rate, byte rate
        append(UInt16(2)); append(UInt16(16))                        // block align, bits per sample
        data.append(contentsOf: Array("data".utf8)); append(dataSize)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }     // Int16 is little-endian on Apple silicon/Intel
        return data
    }
}
