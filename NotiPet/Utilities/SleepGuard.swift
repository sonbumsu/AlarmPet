// SleepGuard.swift
// "뚜껑 닫아도 깨어 있기": keeps the Mac awake with the lid closed so notifications and
// alarms keep working. Uses `pmset -a disablesleep`, which needs root:
//
//   - The first time, the user approves one admin prompt that installs a sudoers rule
//     (/etc/sudoers.d/notipet) allowing exactly `pmset -a disablesleep 0|1`, nothing else.
//   - After that NotiPet flips it with `sudo -n`, so it can also turn it back off on its own:
//     when NotiPet quits, when the battery drops below 20 %, or on the next launch if
//     NotiPet crashed while it was on.

import AppKit
import IOKit.ps

final class SleepGuard: ObservableObject {

    static let shared = SleepGuard()

    /// Sleep is currently disabled by us.
    @Published private(set) var isOn = false

    private enum Constants {
        static let rulePath = "/etc/sudoers.d/notipet"
        static let pmset = "/usr/bin/pmset"
        /// Remembers that we left sleep disabled, so a crash doesn't leave the Mac sleepless.
        static let activeKey = "sleepGuardActive"
        static let minimumBattery = 20
        static let batteryCheckInterval: TimeInterval = 60
    }

    enum Failure: Error {
        case cancelled
        case setupFailed(String)
        case pmsetFailed
    }

    private let defaults: UserDefaults
    private var batteryTimer: Timer?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Left on by a previous run that didn't get to clean up.
        if defaults.bool(forKey: Constants.activeKey) {
            _ = runPmset(disableSleep: false)
            defaults.set(false, forKey: Constants.activeKey)
        }
    }

    var isSetUp: Bool { FileManager.default.fileExists(atPath: Constants.rulePath) }

    // MARK: - On / off

    /// Turns it on, installing the sudoers rule first if needed (shows the admin prompt).
    func turnOn() -> Result<Void, Failure> {
        if !isSetUp || !runPmset(disableSleep: true) {
            if case .failure(let error) = installRule() { return .failure(error) }
            guard runPmset(disableSleep: true) else { return .failure(.pmsetFailed) }
        }
        defaults.set(true, forKey: Constants.activeKey)
        isOn = true
        startBatteryWatch()
        return .success(())
    }

    func turnOff() {
        guard isOn else { return }
        _ = runPmset(disableSleep: false)
        defaults.set(false, forKey: Constants.activeKey)
        isOn = false
        batteryTimer?.invalidate()
        batteryTimer = nil
    }

    // MARK: - Menu

    /// "뚜껑 닫아도 깨어 있기" with a checkmark, for the menu bar and pet right-click menus.
    func menuItem(action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "뚜껑 닫아도 깨어 있기", action: action, keyEquivalent: "")
        item.state = isOn ? .on : .off
        item.toolTip = "뚜껑을 닫아도 맥이 잠들지 않아 알림·알람이 계속 와요. 배터리가 20% 아래로 떨어지거나 알림펫을 끄면 저절로 꺼져요."
        return item
    }

    /// Flip it from a menu, showing an alert if it couldn't be turned on.
    func toggleFromMenu() {
        if isOn { return turnOff() }

        NSApp.activate(ignoringOtherApps: true)   // the admin prompt should come to the front
        switch turnOn() {
        case .success, .failure(.cancelled):
            break
        case .failure(let error):
            let alert = NSAlert()
            alert.messageText = "뚜껑 닫아도 깨어 있기를 켜지 못했어요"
            switch error {
            case .setupFailed(let message): alert.informativeText = message
            default: alert.informativeText = "pmset 설정을 바꾸지 못했어요."
            }
            alert.runModal()
        }
    }

    // MARK: - Battery

    private func startBatteryWatch() {
        batteryTimer?.invalidate()
        batteryTimer = Timer.scheduledTimer(withTimeInterval: Constants.batteryCheckInterval, repeats: true) { [weak self] _ in
            self?.checkBattery()
        }
        checkBattery()
    }

    private func checkBattery() {
        guard let level = Self.batteryLevelOnBattery(), level < Constants.minimumBattery else { return }
        NSLog("SleepGuard: battery at %d%%, letting the Mac sleep again", level)
        turnOff()
    }

    /// Battery percentage while running on battery; nil on AC power or without a battery.
    private static func batteryLevelOnBattery() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? == kIOPSBatteryPowerValue,
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return current * 100 / max
        }
        return nil
    }

    // MARK: - Commands

    /// `sudo -n` never prompts: it fails right away if the rule isn't there.
    private func runPmset(disableSleep: Bool) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", Constants.pmset, "-a", "disablesleep", disableSleep ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// One admin prompt: write a sudoers rule for this user that allows only the two pmset commands.
    private func installRule() -> Result<Void, Failure> {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return .failure(.setupFailed("사용자 이름에 쓸 수 없는 글자가 있어요: \(user)"))
        }
        let rule = "\(user) ALL=(root) NOPASSWD: \(Constants.pmset) -a disablesleep 0, \(Constants.pmset) -a disablesleep 1"
        let shell = "tmp=$(/usr/bin/mktemp) && echo '\(rule)' > $tmp && /usr/sbin/visudo -cf $tmp"
            + " && /usr/bin/install -m 0440 -o root -g wheel $tmp \(Constants.rulePath); rc=$?; /bin/rm -f $tmp; exit $rc"
        let source = "do shell script \"\(shell)\" with prompt \"알림펫이 뚜껑을 닫아도 잠들지 않게 하는 설정을 켜려고 해요.\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if (error[NSAppleScript.errorNumber] as? Int) == -128 { return .failure(.cancelled) }
            return .failure(.setupFailed(error[NSAppleScript.errorMessage] as? String ?? "알 수 없는 오류"))
        }
        return .success(())
    }
}
