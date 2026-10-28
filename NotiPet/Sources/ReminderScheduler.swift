// ReminderScheduler.swift
// Watches every pet's reminders and fires the ones that are due.
//
// Checks once a second whether any occurrence fell between the previous check and now,
// so nothing is skipped even if a tick is late. After the Mac wakes from sleep, alarms that
// were due in the last 30 minutes still ring; older ones are skipped.

import Foundation

final class ReminderScheduler {

    var pets: () -> [OverlayWindowController] = { [] }
    var onFire: ((PetReminder, OverlayWindowController) -> Void)?

    private enum Constants {
        static let tick: TimeInterval = 1
        static let missedGrace: TimeInterval = 30 * 60
    }

    private var timer: Timer?
    private var lastCheck = Date()

    func start() {
        guard timer == nil else { return }
        lastCheck = Date()
        fireSnoozesMissedWhileClosed(now: lastCheck)
        let timer = Timer(timeInterval: Constants.tick, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)   // keep ticking while a menu is open
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The soonest upcoming alarm across all pets (for the menu bar).
    func nextAlarm(now: Date = Date()) -> (date: Date, reminder: PetReminder, pet: OverlayWindowController)? {
        pets().flatMap { pet in
            pet.settings.reminders.compactMap { reminder in
                reminder.nextOccurrence(after: now).map { (date: $0, reminder: reminder, pet: pet) }
            }
        }.min { $0.date < $1.date }
    }

    /// A snooze that came due while the app was closed: ring it if it's recent, otherwise drop it.
    private func fireSnoozesMissedWhileClosed(now: Date) {
        for pet in pets() {
            for reminder in pet.settings.reminders {
                guard let snooze = reminder.snoozeUntil, snooze <= now else { continue }
                pet.settings.clearSnooze(id: reminder.id)
                if now.timeIntervalSince(snooze) <= Constants.missedGrace {
                    onFire?(reminder, pet)
                }
            }
        }
    }

    private func tick() {
        let now = Date()
        defer { lastCheck = now }
        guard now > lastCheck else { return }   // clock moved backwards

        for pet in pets() {
            for reminder in pet.settings.reminders {
                guard let due = reminder.nextOccurrence(after: lastCheck), due <= now else { continue }
                if now.timeIntervalSince(due) <= Constants.missedGrace {
                    onFire?(reminder, pet)
                }
                if let snooze = reminder.snoozeUntil, snooze <= now {
                    pet.settings.clearSnooze(id: reminder.id)
                }
                if reminder.isOnce, reminder.enabled, let once = reminder.onceDate, once <= now {
                    pet.settings.setReminder(id: reminder.id, enabled: false)
                }
            }
        }
    }
}
