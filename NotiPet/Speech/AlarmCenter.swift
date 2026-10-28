// AlarmCenter.swift
// Rings reminders like an alarm clock: looping sound that gets louder, the pet shakes,
// and a bubble with [5분 뒤 다시] / [끄기] stays until the user answers.
// One alarm per pet at a time; more alarms for the same pet wait their turn.

import AppKit
import SwiftUI

final class AlarmCenter {

    /// Called when a pet starts/stops having an alarm up (speech bubbles pause meanwhile).
    var onRingingChanged: ((OverlayWindowController, Bool) -> Void)?
    /// Save a snooze with the reminder (survives restarts). Return false if it can't be saved
    /// (e.g. the test alarm isn't in the list) — then it's kept in memory instead.
    var onSnooze: ((PetReminder, OverlayWindowController, Date) -> Bool)?

    private enum Constants {
        /// Stop the sound (but keep the bubble, marked "놓친 알람") after this long.
        static let ringTimeout: TimeInterval = 10 * 60
        static let snoozeMinutes = 5
        static let gapBetweenAlarms: TimeInterval = 0.5
    }

    private final class Ringing {
        let reminder: PetReminder
        weak var pet: OverlayWindowController?
        let bubble = SpeechBubbleController()
        let player: AlarmPlayer
        var timeout: DispatchWorkItem?

        init(reminder: PetReminder, pet: OverlayWindowController) {
            self.reminder = reminder
            self.pet = pet
            self.player = AlarmPlayer(soundName: pet.settings.alarmSoundName, volume: pet.settings.alarmVolume)
        }
    }

    private var ringing: [String: Ringing] = [:]          // petID → current alarm
    private var waiting: [String: [PetReminder]] = [:]    // petID → alarms queued behind it
    private var snoozes: [UUID: DispatchWorkItem] = [:]

    var ringingCount: Int { ringing.count }

    // MARK: - Ring

    func ring(_ reminder: PetReminder, on pet: OverlayWindowController) {
        let id = pet.settings.instanceID
        if ringing[id] != nil {
            waiting[id, default: []].append(reminder)
            return
        }

        if !pet.isVisible { pet.setVisible(true) }   // a hidden pet comes back to ring
        let alarm = Ringing(reminder: reminder, pet: pet)
        ringing[id] = alarm

        pet.setRinging(true)
        onRingingChanged?(pet, true)
        present(alarm, missed: false)
        alarm.player.start()

        let timeout = DispatchWorkItem { [weak self, weak alarm] in
            guard let self, let alarm, let pet = alarm.pet else { return }
            alarm.player.stop()
            pet.setRinging(true, animate: false)
            self.present(alarm, missed: true)
        }
        alarm.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.ringTimeout, execute: timeout)
    }

    // MARK: - Answer

    func stop(petID: String) {
        guard let alarm = ringing.removeValue(forKey: petID) else { return }
        alarm.timeout?.cancel()
        alarm.player.stop()
        alarm.bubble.hide()

        guard let pet = alarm.pet else { return }
        if var queue = waiting[petID], !queue.isEmpty {
            let next = queue.removeFirst()
            waiting[petID] = queue
            pet.setRinging(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.gapBetweenAlarms) { [weak self, weak pet] in
                guard let self, let pet else { return }
                self.ring(next, on: pet)
            }
        } else {
            pet.setRinging(false)
            onRingingChanged?(pet, false)
        }
    }

    func snooze(petID: String) {
        guard let alarm = ringing[petID], let pet = alarm.pet else { return }
        let reminder = alarm.reminder
        stop(petID: petID)

        let fireAt = Date().addingTimeInterval(TimeInterval(Constants.snoozeMinutes * 60))
        if onSnooze?(reminder, pet, fireAt) == true { return }   // the scheduler will ring it

        let token = UUID()
        let work = DispatchWorkItem { [weak self, weak pet] in
            guard let self, let pet else { return }
            self.snoozes[token] = nil
            self.ring(reminder, on: pet)
        }
        snoozes[token] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(Constants.snoozeMinutes * 60), execute: work)
    }

    func stopAll() {
        for petID in Array(ringing.keys) {
            waiting[petID] = nil
            stop(petID: petID)
        }
    }

    /// The pet is being removed: silence it and forget anything queued.
    func cancel(petID: String) {
        waiting[petID] = nil
        stop(petID: petID)
    }

    // MARK: - Bubble

    private func present(_ alarm: Ringing, missed: Bool) {
        guard let pet = alarm.pet else { return }
        let id = pet.settings.instanceID
        let size = CGFloat(pet.settings.bubbleSize)
        let reminder = alarm.reminder
        alarm.bubble.present(on: pet, maxViewWidth: AlarmBubbleView.maxViewWidth(size: size)) { [weak self] layout in
            AnyView(AlarmBubbleView(reminder: reminder, layout: layout, size: size, missed: missed,
                                    onSnooze: { self?.snooze(petID: id) },
                                    onStop: { self?.stop(petID: id) }))
        }
    }
}
