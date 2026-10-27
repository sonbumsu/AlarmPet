// SpeechQueue.swift
// Routes PetMessages from every source to the pets that should say them.
// Each pet has its own PetSpeaker (queue + bubble + sound), configured by that pet's settings,
// so several pets can talk at once — e.g. one says KakaoTalk, another says Discord.

import AppKit
import AVFoundation

final class SpeechQueue {

    /// All pets, in menu order.
    var pets: () -> [OverlayWindowController] = { [] }
    var onRecentChanged: (() -> Void)?

    private(set) var recent: [PetMessage] = []

    private let settings: NotificationSettings
    private var speakers: [String: PetSpeaker] = [:]

    private enum Constants {
        static let recentLimit = 10
    }

    init(settings: NotificationSettings = .shared) {
        self.settings = settings
    }

    // MARK: - Public

    /// `force` skips app filters and the master switch (test bubbles).
    func enqueue(_ raw: PetMessage, force: Bool = false) {
        var message = raw
        message.sourceApp = raw.app
        message.app = settings.displayName(for: raw.app)

        let listeners = self.listeners(for: raw, displayName: message.app, force: force)
        guard force || !listeners.isEmpty else { return }

        recent.insert(message, at: 0)
        if recent.count > Constants.recentLimit { recent.removeLast() }
        onRecentChanged?()

        guard force || settings.bubbleEnabled else { return }
        for pet in listeners {
            speaker(for: pet).enqueue(message)
        }
    }

    /// True when at least one pet would put this message in a bubble right now.
    /// Used to decide whether the original system banner may be closed.
    func wouldShow(_ raw: PetMessage) -> Bool {
        settings.bubbleEnabled
            && !listeners(for: raw, displayName: settings.displayName(for: raw.app), force: false).isEmpty
    }

    /// An alarm started on this pet: put its current bubble back in line and wait.
    func suspend(petID: String) {
        speakers[petID]?.suspend()
    }

    /// The alarm stopped: carry on with whatever was waiting.
    func resume(petID: String) {
        speakers[petID]?.resume()
    }

    func removeSpeaker(for instanceID: String) {
        speakers[instanceID]?.stop()
        speakers.removeValue(forKey: instanceID)
    }

    // MARK: - Routing

    private func listeners(for raw: PetMessage, displayName: String, force: Bool) -> [OverlayWindowController] {
        let visible = pets().filter(\.isVisible)
        if let target = raw.target {
            return visible.filter { $0.settings.matches(target: target) && (force || $0.settings.speaksNotifications) }
        }
        if force { return visible }
        return visible.filter { $0.settings.speaks(app: raw.app, displayName: displayName) }
    }

    private func speaker(for pet: OverlayWindowController) -> PetSpeaker {
        let id = pet.settings.instanceID
        if let existing = speakers[id], existing.pet === pet { return existing }
        let created = PetSpeaker(pet: pet)
        speakers[id] = created
        return created
    }
}

// MARK: - One pet's voice

/// Shows one pet's messages one at a time, using that pet's bubble / sound / TTS settings.
final class PetSpeaker {

    private(set) weak var pet: OverlayWindowController?

    private let bubble = SpeechBubbleController()
    private let synthesizer = AVSpeechSynthesizer()
    private var queue: [PetMessage] = []
    private var current: PetMessage?
    private var isBetweenMessages = false
    private var hideWork: DispatchWorkItem?

    private enum Constants {
        static let gapBetweenMessages: TimeInterval = 0.3
        static let soundLeadIn: TimeInterval = 0.35
    }

    init(pet: OverlayWindowController) {
        self.pet = pet
        bubble.onTap = { [weak self] in self?.finishCurrent() }
    }

    func enqueue(_ message: PetMessage) {
        queue.append(message)
        if current == nil && !isBetweenMessages { showNext() }
    }

    func stop() {
        queue.removeAll()
        finishCurrent()
    }

    func suspend() {
        guard let current else { return }
        queue.insert(current, at: 0)
        hideWork?.cancel()
        hideWork = nil
        pet?.setTalking(false)
        self.current = nil
        bubble.hide()
    }

    func resume() {
        if current == nil && !isBetweenMessages { showNext() }
    }

    func finishCurrent() {
        hideWork?.cancel()
        hideWork = nil
        pet?.setTalking(false)
        current = nil
        bubble.hide()

        guard !queue.isEmpty else { return }
        isBetweenMessages = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.gapBetweenMessages) { [weak self] in
            self?.isBetweenMessages = false
            self?.showNext()
        }
    }

    private func showNext() {
        guard current == nil, !queue.isEmpty else { return }
        guard let pet, !pet.isAlarmRinging else { return }   // resumed when the alarm stops
        guard pet.isVisible else {
            queue.removeAll()
            return
        }

        let settings = pet.settings
        let message = queue.removeFirst()
        current = message
        bubble.show(message, on: pet)
        PetSound.play(settings.soundName, volume: settings.soundVolume)
        if settings.bounceWhileTalking { pet.setTalking(true) }
        if settings.ttsEnabled {
            // Let the sound effect finish before the voice starts.
            DispatchQueue.main.asyncAfter(deadline: .now() + (settings.soundName.isEmpty ? 0 : Constants.soundLeadIn)) { [weak self] in
                self?.speak(message)
            }
        }

        let work = DispatchWorkItem { [weak self] in self?.finishCurrent() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.bubbleDuration, execute: work)
    }

    private func speak(_ message: PetMessage) {
        let utterance = AVSpeechUtterance(string: message.spokenText)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        synthesizer.speak(utterance)
    }
}
