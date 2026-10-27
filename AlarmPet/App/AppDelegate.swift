// AppDelegate.swift
// Manages the collection of pets, the menubar controller, and two pipelines:
//   notifications: sources (local HTTP / system banners) → SpeechQueue → each matching pet's bubble
//   reminders:     each pet's reminders → ReminderScheduler → AlarmCenter (rings until answered)

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - State
    private var pets: [OverlayWindowController] = []
    private let petsStore = PetsStore()
    private var menuBarController: MenuBarController!

    // MARK: - Notifications
    private let notificationSettings = NotificationSettings.shared
    private let speechQueue = SpeechQueue()
    private let reminderScheduler = ReminderScheduler()
    private let alarmCenter = AlarmCenter()
    private let accessibilitySource = AccessibilitySource()
    private var localServerSource: LocalServerSource?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController()
        menuBarController.onAddPet    = { [weak self] in self?.addPet() }
        menuBarController.onAddDefaultPet = { [weak self] in self?.addPlaceholderPet() }
        menuBarController.onRemovePet = { [weak self] id in self?.removePet(id: id) }
        menuBarController.onTestBubble = { [weak self] in self?.sayTestMessage(to: nil) }
        menuBarController.onTestBubbleForPet = { [weak self] id in self?.sayTestMessage(to: id) }
        menuBarController.onTestAlarmForPet = { [weak self] id in self?.ringTestAlarm(petID: id) }
        menuBarController.onStopAllAlarms = { [weak self] in self?.alarmCenter.stopAll() }
        menuBarController.ringingAlarmCount = { [weak self] in self?.alarmCenter.ringingCount ?? 0 }
        menuBarController.nextAlarmText = { [weak self] in self?.nextAlarmText() }
        menuBarController.onRequestAccessibility = { AccessibilitySource.requestPermission() }
        menuBarController.recentMessages = { [weak self] in self?.speechQueue.recent ?? [] }

        restorePets()
        setupNotifications()
        setupReminders()

        // Build the installed-app name index (~0.1 s) now rather than on the first notification.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { _ = AppDirectory.names(for: "") }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        petsStore.flush()
    }

    // MARK: - Pets

    private func restorePets() {
        let savedRecords = petsStore.loadRecords()

        if savedRecords.isEmpty {
            addPlaceholderPet()
            return
        }

        for record in savedRecords {
            let wc = makeController(record: record)
            if let bookmark = wc.settings.assetBookmark {
                guard wc.loadAssetFromBookmark(bookmark) else { continue }
            } else {
                wc.loadPlaceholder()
            }
            wc.showWindow(nil)
            pets.append(wc)
        }
        menuBarController.update(pets: pets)
    }

    func addPet() {
        let urls = menuBarController.openAddPetsPicker()
        guard !urls.isEmpty else { return }

        var didAddAnyPet = false
        for url in urls {
            if addPet(for: url) {
                didAddAnyPet = true
            }
        }

        if didAddAnyPet {
            menuBarController.update(pets: pets)
        }
    }

    func removePet(id: String) {
        guard let idx = pets.firstIndex(where: { $0.settings.instanceID == id }) else { return }
        let wc = pets[idx]
        wc.window?.close()
        pets.remove(at: idx)
        speechQueue.removeSpeaker(for: id)
        alarmCenter.cancel(petID: id)
        petsStore.remove(instanceID: id)
        menuBarController.update(pets: pets)
    }

    private func addPet(for url: URL) -> Bool {
        let wc = makeController(record: petsStore.makeNewPetRecord())
        guard wc.loadAsset(url: url) else { return false }

        wc.showWindow(nil)
        pets.append(wc)
        petsStore.upsert(wc.settings.toRecord())
        return true
    }

    /// The built-in alarm-clock cat: on first launch, or from the menu ("기본 펫 추가").
    private func addPlaceholderPet() {
        let wc = makeController(record: petsStore.makeNewPetRecord())
        wc.loadPlaceholder()
        wc.showWindow(nil)
        pets.append(wc)
        petsStore.upsert(wc.settings.toRecord())
        menuBarController.update(pets: pets)
    }

    private func makeController(record: PetRecord) -> OverlayWindowController {
        let settings = AppSettings(record: record) { [weak self] settings in
            self?.petsStore.upsert(settings.toRecord())
        }
        let wc = OverlayWindowController(settings: settings)
        wc.onOpenSettings = { [weak self] pet in self?.menuBarController.showSettingsPanel(for: pet) }
        return wc
    }

    // MARK: - Notifications

    private func setupNotifications() {
        speechQueue.pets = { [weak self] in self?.pets ?? [] }

        let deliver: (PetMessage) -> Void = { [weak self] message in
            self?.speechQueue.enqueue(message)
        }
        accessibilitySource.onMessage = deliver
        // Only close the real banner if the pet is definitely going to say it.
        accessibilitySource.shouldDismissOriginal = { [weak self] message in
            guard let self else { return false }
            return self.notificationSettings.hideOriginalBanners && self.speechQueue.wouldShow(message)
        }

        notificationSettings.$localServerEnabled
            .combineLatest(notificationSettings.$localServerPort)
            .sink { [weak self] enabled, port in
                self?.restartLocalServer(enabled: enabled, port: port, deliver: deliver)
            }
            .store(in: &cancellables)

        notificationSettings.$systemNotificationsEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    if !AccessibilitySource.isTrusted { AccessibilitySource.requestPermission() }
                    self.accessibilitySource.start()
                } else {
                    self.accessibilitySource.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func restartLocalServer(enabled: Bool, port: Int, deliver: @escaping (PetMessage) -> Void) {
        localServerSource?.stop()
        localServerSource = nil
        notificationSettings.localServerError = nil
        guard enabled, let port = UInt16(exactly: port) else { return }
        let server = LocalServerSource(port: port)
        server.onMessage = deliver
        server.onStatusChange = { [weak self] error in
            self?.notificationSettings.localServerError = error
        }
        server.start()
        localServerSource = server
    }

    /// `petID` nil = every visible pet.
    // MARK: - Reminders

    private func setupReminders() {
        reminderScheduler.pets = { [weak self] in self?.pets ?? [] }
        reminderScheduler.onFire = { [weak self] reminder, pet in
            self?.alarmCenter.ring(reminder, on: pet)
        }
        alarmCenter.onSnooze = { reminder, pet, date in
            pet.settings.snoozeReminder(id: reminder.id, until: date)
        }
        // Notification bubbles wait while a pet's alarm is up, then continue.
        alarmCenter.onRingingChanged = { [weak self] pet, ringing in
            let id = pet.settings.instanceID
            if ringing { self?.speechQueue.suspend(petID: id) } else { self?.speechQueue.resume(petID: id) }
        }
        reminderScheduler.start()
    }

    private func ringTestAlarm(petID: String) {
        guard let pet = pets.first(where: { $0.settings.instanceID == petID }) else { return }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        alarmCenter.ring(PetReminder(title: "알람 테스트", hour: now.hour ?? 0, minute: now.minute ?? 0), on: pet)
    }

    private func nextAlarmText() -> String? {
        guard let next = reminderScheduler.nextAlarm() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(next.date) ? "HH:mm" : "M/d HH:mm"
        let title = next.reminder.title.isEmpty ? "리마인더" : next.reminder.title
        return "\(formatter.string(from: next.date)) \(next.pet.settings.label) · \(title)"
    }

    private func sayTestMessage(to petID: String?) {
        var message = PetMessage(app: "테스트", body: "테스트입니다.", sender: "테스트")
        message.target = petID
        speechQueue.enqueue(message, force: true)
    }
}
