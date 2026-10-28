// ScreenActivity.swift
// Whether anyone can see the screen right now. False while the display sleeps, the screen
// is locked, or the screen saver runs — pets stop animating then (it keeps WindowServer
// compositing the overlay windows for nobody), while notifications and alarms keep working.

import AppKit
import Combine

final class ScreenActivity: ObservableObject {

    static let shared = ScreenActivity()

    @Published private(set) var isVisible = true

    private var displayAsleep = false   { didSet { update() } }
    private var locked = false          { didSet { update() } }
    private var screenSaver = false     { didSet { update() } }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.screensDidSleepNotification.rawValue) { $0.displayAsleep = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification.rawValue) { $0.displayAsleep = false }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, "com.apple.screenIsLocked") { $0.locked = true }
        observe(distributed, "com.apple.screenIsUnlocked") { $0.locked = false }
        observe(distributed, "com.apple.screensaver.didstart") { $0.screenSaver = true }
        observe(distributed, "com.apple.screensaver.didstop") { $0.screenSaver = false }
    }

    deinit {
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func observe(_ center: NotificationCenter, _ name: String, _ change: @escaping (ScreenActivity) -> Void) {
        let token = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
            if let self { change(self) }
        }
        observers.append((center, token))
    }

    private func update() {
        let visible = !displayAsleep && !locked && !screenSaver
        if visible != isVisible { isVisible = visible }
    }
}
