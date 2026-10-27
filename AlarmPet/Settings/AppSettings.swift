// AppSettings.swift
// Per-instance settings for one pet.
// Observable so SwiftUI views react to changes in real time.

import Foundation
import Combine
import AppKit

final class AppSettings: ObservableObject {

    // MARK: - Instance identity
    let instanceID: String   // e.g. "pet-1", "pet-2", …
    private var onChange: ((AppSettings) -> Void)?
    private var isInitializing = true

    // MARK: - Published Properties

    @Published var positionX: Double   { didSet { notifyChangeIfNeeded() } }
    @Published var positionY: Double   { didSet { notifyChangeIfNeeded() } }
    @Published var scale: Double       { didSet { notifyChangeIfNeeded() } }
    @Published var rotation: Double    { didSet { notifyChangeIfNeeded() } }   // degrees, clockwise, -180...180
    @Published var opacity: Double     { didSet { notifyChangeIfNeeded() } }
    @Published var speed: Double       { didSet { notifyChangeIfNeeded() } }
    @Published var clickThrough: Bool  { didSet { notifyChangeIfNeeded() } }
    @Published var lockPosition: Bool  { didSet { notifyChangeIfNeeded() } }
    @Published var alwaysOnTop: Bool   { didSet { notifyChangeIfNeeded() } }
    @Published var playing: Bool       { didSet { notifyChangeIfNeeded() } }
    @Published var label: String       { didSet { notifyChangeIfNeeded() } }

    // Speech
    @Published var speaksNotifications: Bool { didSet { notifyChangeIfNeeded() } }
    @Published var bubbleDuration: Double    { didSet { notifyChangeIfNeeded() } }
    @Published var bubbleSize: Double        { didSet { notifyChangeIfNeeded() } }
    @Published var soundName: String         { didSet { notifyChangeIfNeeded() } }
    @Published var soundVolume: Double       { didSet { notifyChangeIfNeeded() } }
    @Published var ttsEnabled: Bool          { didSet { notifyChangeIfNeeded() } }
    @Published var bounceWhileTalking: Bool  { didSet { notifyChangeIfNeeded() } }
    @Published var allowedApps: String       { didSet { notifyChangeIfNeeded() } }
    @Published var blockedApps: String       { didSet { notifyChangeIfNeeded() } }

    // Reminders
    @Published var reminders: [PetReminder]  { didSet { notifyChangeIfNeeded() } }
    @Published var alarmSoundName: String    { didSet { notifyChangeIfNeeded() } }
    @Published var alarmVolume: Double       { didSet { notifyChangeIfNeeded() } }

    // Security-scoped bookmark for the last imported asset (nil = built-in default pet).
    // Published so the settings panel knows whether "기본 펫으로 바꾸기" applies.
    @Published var assetBookmark: Data? { didSet { notifyChangeIfNeeded() } }

    // MARK: - Init

    init(record: PetRecord, onChange: ((AppSettings) -> Void)? = nil) {
        self.instanceID = record.instanceID
        self.positionX = record.positionX
        self.positionY = record.positionY
        self.scale = record.scale
        self.rotation = record.rotation
        self.opacity = record.opacity
        self.speed = record.speed
        self.clickThrough = record.clickThrough
        self.lockPosition = record.lockPosition
        self.alwaysOnTop = record.alwaysOnTop
        self.playing = record.playing
        self.label = record.label
        self.assetBookmark = record.assetBookmark
        self.speaksNotifications = record.speaksNotifications
        self.bubbleDuration = record.bubbleDuration
        self.bubbleSize = record.bubbleSize
        self.soundName = record.soundName
        self.soundVolume = record.soundVolume
        self.ttsEnabled = record.ttsEnabled
        self.bounceWhileTalking = record.bounceWhileTalking
        self.allowedApps = record.allowedApps
        self.blockedApps = record.blockedApps
        self.reminders = record.reminders
        self.alarmSoundName = record.alarmSoundName
        self.alarmVolume = record.alarmVolume
        self.onChange = onChange
        self.isInitializing = false
    }

    // MARK: - Helpers

    /// Position is the pet's center in screen coordinates, so it stays put
    /// while the window grows or shrinks for rotation/scale.
    func savePosition(_ point: NSPoint) {
        positionX = point.x
        positionY = point.y
    }

    func savedPosition() -> NSPoint {
        NSPoint(x: positionX, y: positionY)
    }

    func toRecord() -> PetRecord {
        PetRecord(
            instanceID: instanceID,
            positionX: positionX,
            positionY: positionY,
            scale: scale,
            rotation: rotation,
            opacity: opacity,
            speed: speed,
            clickThrough: clickThrough,
            lockPosition: lockPosition,
            alwaysOnTop: alwaysOnTop,
            playing: playing,
            label: label,
            assetBookmark: assetBookmark,
            speaksNotifications: speaksNotifications,
            bubbleDuration: bubbleDuration,
            bubbleSize: bubbleSize,
            soundName: soundName,
            soundVolume: soundVolume,
            ttsEnabled: ttsEnabled,
            bounceWhileTalking: bounceWhileTalking,
            allowedApps: allowedApps,
            blockedApps: blockedApps,
            reminders: reminders,
            alarmSoundName: alarmSoundName,
            alarmVolume: alarmVolume
        )
    }

    // MARK: - Reminder helpers

    func addReminder(_ reminder: PetReminder) {
        reminders.append(reminder)
        sortReminders()
    }

    /// Replace the reminder with the same id (editing).
    func updateReminder(_ reminder: PetReminder) {
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index] = reminder
        sortReminders()
    }

    /// Returns false if the reminder isn't in this pet's list (e.g. the "알람 테스트" alarm).
    @discardableResult
    func snoozeReminder(id: UUID, until date: Date) -> Bool {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return false }
        reminders[index].snoozeUntil = date
        return true
    }

    func clearSnooze(id: UUID) {
        guard let index = reminders.firstIndex(where: { $0.id == id }), reminders[index].snoozeUntil != nil else { return }
        reminders[index].snoozeUntil = nil
    }

    private func sortReminders() {
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    func removeReminder(id: UUID) {
        reminders.removeAll { $0.id == id }
    }

    func setReminder(id: UUID, enabled: Bool) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        var reminder = reminders[index]
        reminder.enabled = enabled
        if !enabled { reminder.snoozeUntil = nil }   // switching off also cancels a pending snooze
        // Re-enabling a one-time reminder that already rang: ring at its time again (next occurrence).
        if enabled, reminder.isOnce, (reminder.onceDate ?? .distantPast) <= Date() {
            reminder = .once(title: reminder.title, hour: reminder.hour, minute: reminder.minute)
            reminder.id = reminders[index].id
        }
        reminders[index] = reminder
    }

    // MARK: - Speech helpers

    /// Whether this pet wants to say notifications from `app`.
    /// Filters match the original app name, its display name (alias), or any other name
    /// the installed app goes by — so "카카오톡" and "KakaoTalk" both work.
    func speaks(app: String, displayName: String) -> Bool {
        guard speaksNotifications else { return false }
        let names = AppDirectory.names(for: app).union(AppDirectory.names(for: displayName)).map { $0.lowercased() }
        let allowed = Self.list(allowedApps)
        let blocked = Self.list(blockedApps)
        if names.contains(where: blocked.contains) { return false }
        return allowed.isEmpty || names.contains(where: allowed.contains)
    }

    /// Local HTTP can address a pet by its name ("나비") or id ("pet-1").
    func matches(target: String) -> Bool {
        target.caseInsensitiveCompare(label) == .orderedSame || target == instanceID
    }

    private static func list(_ text: String) -> Set<String> {
        Set(text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    // MARK: - Persistence callback

    private func notifyChangeIfNeeded() {
        guard !isInitializing else { return }
        onChange?(self)
    }
}
