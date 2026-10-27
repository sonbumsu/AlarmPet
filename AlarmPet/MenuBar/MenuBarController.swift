// MenuBarController.swift
// Manages the NSStatusItem and its dropdown menu.
// Supports multiple pets — each with its own settings panel.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class MenuBarController: NSObject {

    // MARK: - Callbacks to AppDelegate
    var onAddPet: (() -> Void)?
    var onAddDefaultPet: (() -> Void)?
    var onRemovePet: ((String) -> Void)?   // instanceID
    var onTestBubble: (() -> Void)?
    var onTestBubbleForPet: ((String) -> Void)?   // instanceID
    var onTestAlarmForPet: ((String) -> Void)?    // instanceID
    var onStopAllAlarms: (() -> Void)?
    var ringingAlarmCount: () -> Int = { 0 }
    /// "07:30 kurukuru · 일어나기" for the soonest alarm, nil if none.
    var nextAlarmText: () -> String? = { nil }
    var onRequestAccessibility: (() -> Void)?
    var recentMessages: () -> [PetMessage] = { [] }

    // MARK: - Status Item
    private var statusItem: NSStatusItem!

    // MARK: - Per-pet panels  [instanceID: NSPanel]
    private var settingsPanels: [String: NSPanel] = [:]
    private var settingsTabs: [String: SettingsTabs] = [:]
    private var notificationPanel: NSPanel?

    // MARK: - Pets snapshot (kept in sync by AppDelegate)
    private(set) var pets: [OverlayWindowController] = []

    // MARK: - Init

    override init() {
        super.init()
        setupStatusItem()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.toolTip = "알림펫"
            button.action = #selector(statusButtonClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusButtonClicked(_ sender: NSStatusBarButton) {
        showContextMenu(sender)
    }

    // MARK: - Context Menu

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        // ── Ringing alarms ────────────────────────────────────────────────
        let ringing = ringingAlarmCount()
        if ringing > 0 {
            let stopItem = NSMenuItem(title: ringing > 1 ? "⏰ 울리는 알람 모두 끄기 (\(ringing))" : "⏰ 알람 끄기",
                                      action: #selector(stopAllAlarms), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            menu.addItem(.separator())
        }

        // ── Add pet ──────────────────────────────────────────────────────
        let addItem = NSMenuItem(title: "펫 추가…", action: #selector(addPet), keyEquivalent: "n")
        addItem.target = self
        menu.addItem(addItem)

        let addDefaultItem = NSMenuItem(title: "기본 펫 추가 (알람시계 고양이)", action: #selector(addDefaultPet), keyEquivalent: "")
        addDefaultItem.target = self
        menu.addItem(addDefaultItem)

        // ── Hide All / Show All ───────────────────────────────────────────
        if !pets.isEmpty {
            let allHidden = pets.allSatisfy { !$0.isVisible }
            let hideAllItem = NSMenuItem(
                title: allHidden ? "모두 보이기" : "모두 숨기기",
                action: #selector(toggleHideAll),
                keyEquivalent: "h"
            )
            hideAllItem.target = self
            menu.addItem(hideAllItem)
        }

        // ── Per-pet section ───────────────────────────────────────────────
        if !pets.isEmpty {
            menu.addItem(.separator())
            for (idx, pet) in pets.enumerated() {
                // Header: user's label — clicking opens Settings
                let headerItem = NSMenuItem(
                    title: pet.settings.label,
                    action: #selector(openPetSettings(_:)),
                    keyEquivalent: ""
                )
                headerItem.target = self
                headerItem.representedObject = pet.settings.instanceID
                // Show hide/show state with a bullet
                headerItem.state = pet.isVisible ? .on : .off
                menu.addItem(headerItem)

                let settingsItem = NSMenuItem(
                    title: "  설정…",
                    action: #selector(openPetSettings(_:)),
                    keyEquivalent: ""
                )
                settingsItem.target = self
                settingsItem.representedObject = pet.settings.instanceID
                menu.addItem(settingsItem)

                let hideItem = NSMenuItem(
                    title: pet.isVisible ? "  숨기기" : "  보이기",
                    action: #selector(togglePetVisibility(_:)),
                    keyEquivalent: ""
                )
                hideItem.target = self
                hideItem.representedObject = pet.settings.instanceID
                menu.addItem(hideItem)

                let removeItem = NSMenuItem(
                    title: "  삭제",
                    action: #selector(removePet(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.representedObject = pet.settings.instanceID
                menu.addItem(removeItem)

                if idx < pets.count - 1 { menu.addItem(.separator()) }
            }
        }

        // ── Notifications ─────────────────────────────────────────────────
        menu.addItem(.separator())
        let bubbleItem = NSMenuItem(title: "알림 말풍선 (모든 펫)", action: #selector(toggleBubble), keyEquivalent: "")
        bubbleItem.target = self
        bubbleItem.state = NotificationSettings.shared.bubbleEnabled ? .on : .off
        menu.addItem(bubbleItem)

        let notificationSettingsItem = NSMenuItem(title: "알림 설정…", action: #selector(openNotificationSettings), keyEquivalent: ",")
        notificationSettingsItem.target = self
        menu.addItem(notificationSettingsItem)

        let testItem = NSMenuItem(title: "말풍선 테스트", action: #selector(testBubble), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        // ── Reminders ─────────────────────────────────────────────────────
        menu.addItem(.separator())
        if pets.count == 1, let pet = pets.first {
            let reminderItem = NSMenuItem(title: "리마인더…", action: #selector(openReminders(_:)), keyEquivalent: "r")
            reminderItem.target = self
            reminderItem.representedObject = pet.settings.instanceID
            menu.addItem(reminderItem)
        } else if !pets.isEmpty {
            let reminderItem = NSMenuItem(title: "리마인더", action: nil, keyEquivalent: "")
            let petsMenu = NSMenu()
            for pet in pets {
                let item = NSMenuItem(title: "\(pet.settings.label)…", action: #selector(openReminders(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pet.settings.instanceID
                petsMenu.addItem(item)
            }
            reminderItem.submenu = petsMenu
            menu.addItem(reminderItem)
        }
        let nextItem = NSMenuItem(title: nextAlarmText().map { "다음 알람: \($0)" } ?? "예정된 알람 없음",
                                  action: nil, keyEquivalent: "")
        nextItem.isEnabled = false
        menu.addItem(nextItem)

        menu.addItem(.separator())

        let recentItem = NSMenuItem(title: "최근 알림", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu()
        let recent = recentMessages()
        if recent.isEmpty {
            recentMenu.addItem(withTitle: "아직 없음", action: nil, keyEquivalent: "").isEnabled = false
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            for message in recent {
                let title = "[\(formatter.string(from: message.date))] \(message.bubbleText)"
                let item = NSMenuItem(title: title.count > 60 ? String(title.prefix(60)) + "…" : title,
                                      action: nil, keyEquivalent: "")
                item.isEnabled = false
                recentMenu.addItem(item)
            }
        }
        recentItem.submenu = recentMenu
        menu.addItem(recentItem)

        // ── Quit ──────────────────────────────────────────────────────────
        menu.addItem(.separator())
        menu.addItem(withTitle: "알림펫 종료",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Actions

    @objc private func addPet() {
        onAddPet?()
    }

    @objc private func addDefaultPet() {
        onAddDefaultPet?()
    }

    @objc private func toggleBubble() {
        NotificationSettings.shared.bubbleEnabled.toggle()
    }

    @objc private func testBubble() {
        onTestBubble?()
    }

    @objc private func openReminders(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let pet = pets.first(where: { $0.settings.instanceID == id })
        else { return }
        showSettingsPanel(for: pet, tab: .reminders)
    }

    @objc private func stopAllAlarms() {
        onStopAllAlarms?()
    }

    @objc private func openNotificationSettings() {
        notificationPanel?.orderOut(nil)
        let view = NotificationSettingsView(
            settings: .shared,
            onTestBubble: { [weak self] in self?.onTestBubble?() },
            onRequestAccessibility: { [weak self] in self?.onRequestAccessibility?() }
        )
        let panel = makePanel(NSHostingController(rootView: view), width: 320)
        panel.title = "알림 설정"
        notificationPanel = panel
        positionBelowStatusItem(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleHideAll() {
        let allHidden = pets.allSatisfy { !$0.isVisible }
        pets.forEach { $0.setVisible(allHidden) }   // if all hidden → show all, else hide all
    }

    @objc private func togglePetVisibility(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let pet = pets.first(where: { $0.settings.instanceID == id })
        else { return }
        pet.setVisible(!pet.isVisible)
    }

    @objc private func openPetSettings(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String,
              let pet = pets.first(where: { $0.settings.instanceID == id }),
              let button = statusItem.button
        else { return }
        toggleSettingsPanel(for: pet, relativeTo: button)
    }

    @objc private func removePet(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        settingsPanels[id]?.orderOut(nil)
        settingsPanels.removeValue(forKey: id)
        onRemovePet?(id)
    }

    // MARK: - Settings Panel

    /// Opened from the pet's right-click menu (or a menu shortcut): show the panel next to the pet.
    func showSettingsPanel(for pet: OverlayWindowController, tab: SettingsTabs.Tab = .pet) {
        let id = pet.settings.instanceID
        settingsPanels[id]?.orderOut(nil)
        let panel = makeSettingsPanel(for: pet)
        settingsTabs[id]?.selected = tab
        settingsPanels[id] = panel

        if let petFrame = pet.window?.frame, let screen = (pet.window?.screen ?? NSScreen.main)?.visibleFrame {
            var x = petFrame.maxX + 8
            if x + panel.frame.width > screen.maxX { x = petFrame.minX - panel.frame.width - 8 }
            let y = min(max(petFrame.midY - panel.frame.height / 2, screen.minY), screen.maxY - panel.frame.height)
            panel.setFrameOrigin(NSPoint(x: max(x, screen.minX), y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func toggleSettingsPanel(for pet: OverlayWindowController, relativeTo button: NSStatusBarButton) {
        let id = pet.settings.instanceID

        if let panel = settingsPanels[id], panel.isVisible {
            panel.orderOut(nil)
            return
        }

        let panel = makeSettingsPanel(for: pet)
        settingsPanels[id] = panel

        positionBelowStatusItem(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsPanel(for pet: OverlayWindowController) -> NSPanel {
        let id = pet.settings.instanceID
        let tabs = SettingsTabs()
        settingsTabs[id] = tabs
        let view = SettingsView(
            settings: pet.settings,
            tabs: tabs,
            onImport: { [weak self, weak pet] in
                guard let self, let pet else { return }
                self.openFilePicker(for: pet)
            },
            onUseDefaultPet: { [weak pet] in pet?.useDefaultPet() },
            onRemove: { [weak self] in
                self?.settingsPanels[id]?.orderOut(nil)
                self?.settingsPanels.removeValue(forKey: id)
                self?.onRemovePet?(id)
            },
            onQuit: { NSApp.terminate(nil) },
            onTestBubble: { [weak self] in self?.onTestBubbleForPet?(id) },
            onTestAlarm: { [weak self] in self?.onTestAlarmForPet?(id) }
        )
        return makePanel(NSHostingController(rootView: view), width: 320)
    }

    private func makePanel<Content: View>(_ hosting: NSHostingController<Content>, width: CGFloat) -> NSPanel {
        hosting.view.setFrameSize(hosting.sizeThatFits(in: NSSize(width: width, height: 900)))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.view.frame.size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = ""
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func positionBelowStatusItem(_ panel: NSPanel) {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.frame)
        var x = buttonRect.midX - panel.frame.width / 2
        if let screen = buttonWindow.screen?.visibleFrame {
            x = min(max(x, screen.minX + 4), screen.maxX - panel.frame.width - 4)
        }
        panel.setFrameOrigin(NSPoint(x: x, y: buttonRect.minY - panel.frame.height - 4))
    }

    // MARK: - File Picker

    func openAddPetsPicker() -> [URL] {
        let panel = makeImportOpenPanel(allowsMultipleSelection: true, petName: nil)
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.urls : []
    }

    func openFilePicker(for pet: OverlayWindowController) {
        settingsPanels[pet.settings.instanceID]?.orderOut(nil)
        let panel = makeImportOpenPanel(allowsMultipleSelection: false, petName: pet.settings.label)

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            _ = pet.loadAsset(url: url)
        }
    }

    private func makeImportOpenPanel(allowsMultipleSelection: Bool, petName: String?) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.allowedContentTypes = [
            UTType.gif,
            UTType.png,
            UTType(filenameExtension: "apng") ?? UTType.png,
            UTType.mpeg4Movie,
            UTType.quickTimeMovie,
            UTType.folder
        ]
        panel.prompt = "열기"

        if let petName {
            panel.message = "\"\(petName)\"에 쓸 애니메이션을 고르세요\n\n지원: GIF · APNG · PNG 시퀀스 폴더 · MP4 · MOV"
        } else {
            panel.message = "펫으로 쓸 애니메이션을 하나 이상 고르세요\n\n지원: GIF · APNG · PNG 시퀀스 폴더 · MP4 · MOV"
        }

        return panel
    }

    // MARK: - Sync

    /// Called by AppDelegate whenever the pets array changes.
    func update(pets: [OverlayWindowController]) {
        self.pets = pets
        let activeIDs = Set(pets.map { $0.settings.instanceID })
        for id in settingsPanels.keys where !activeIDs.contains(id) {
            settingsPanels[id]?.orderOut(nil)
            settingsPanels.removeValue(forKey: id)
            settingsTabs.removeValue(forKey: id)
        }
    }
}
