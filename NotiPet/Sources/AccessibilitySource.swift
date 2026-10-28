// AccessibilitySource.swift
// Reads system notification banners (KakaoTalk, Slack, …) through the Accessibility API,
// and optionally closes the original banner so only the pet's bubble remains.
//
// macOS has no public API for reading other apps' notifications. Banners are drawn by
// the NotificationCenter process (com.apple.notificationcenterui), so we watch its
// AX tree, find notification elements, and turn their texts into PetMessages:
//   title → sender, last text → body, app name → from the stacking identifier / description.
//
// Detection: an AXObserver fires the moment a banner window/element is created, so the
// banner can be closed while it is still sliding in. A slow poll is kept as a fallback.
//
// The AX layout differs between macOS versions, so parsing has several fallbacks.
// Run with NOTIPET_AX_DEBUG=1 to write diagnostics to ~/Library/Logs/NotiPet/ax.log
// (trust state, Notification Center windows, the full AX tree, close attempts).

import AppKit
import ApplicationServices

final class AccessibilitySource: NotificationSource {

    var onMessage: ((PetMessage) -> Void)?
    /// Asked for every new banner; true = close the original banner (the pet will say it instead).
    var shouldDismissOriginal: ((PetMessage) -> Bool)?

    private enum Constants {
        static let bundleID = "com.apple.notificationcenterui"
        static let pollInterval: TimeInterval = 0.5
        /// Re-check shortly after an AX event: banner texts are sometimes filled in a moment later.
        static let followUpDelays: [TimeInterval] = [0.03, 0.1, 0.25]
        static let maxDepth = 16
        /// More "new" notifications than this at once = the user opened Notification Center history.
        static let historyBurst = 3
        static let fallbackApp = "알림"
    }

    private typealias Found = (key: String, message: PetMessage, element: AXUIElement)

    private var timer: Timer?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var visibleKeys: Set<String> = []
    private var primed = false
    private let debug = ProcessInfo.processInfo.environment["NOTIPET_AX_DEBUG"] == "1"
    private var lastDebugState = ""

    // MARK: - Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Lifecycle

    func start() {
        guard timer == nil else { return }
        primed = false
        visibleKeys = []
        timer = Timer.scheduledTimer(withTimeInterval: Constants.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        detachObserver()
    }

    // MARK: - AX observer (fast path)

    private func attachObserverIfNeeded(pid: pid_t) {
        guard observer == nil || observedPID != pid else { return }
        detachObserver()

        // C callback: no captures, `self` comes back through refcon.
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<AccessibilitySource>.fromOpaque(refcon).takeUnretainedValue().bannerDidChange()
        }

        var created: AXObserver?
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }

        let axApp = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification] {
            AXObserverAddNotification(created, axApp, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)

        observer = created
        observedPID = pid
    }

    private func detachObserver() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
    }

    private func bannerDidChange() {
        poll()
        for delay in Constants.followUpDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.poll() }
        }
    }

    // MARK: - Polling

    private func poll() {
        guard timer != nil else { return }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: Constants.bundleID).first
        guard Self.isTrusted, let app else {
            debugState("trusted=\(Self.isTrusted) notificationCenterPID=\(app.map { String($0.processIdentifier) } ?? "none")")
            return
        }

        // (Re)attach when permission was just granted or NotificationCenter restarted.
        attachObserverIfNeeded(pid: app.processIdentifier)

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = children(of: axApp, attribute: kAXWindowsAttribute)
        var found: [Found] = []
        for window in windows {
            collect(in: window, depth: 0, into: &found)
        }

        if debug {
            let roots = windows.isEmpty ? children(of: axApp, attribute: kAXChildrenAttribute) : windows
            let focus = "focusedWindow=\(element(axApp, kAXFocusedWindowAttribute) != nil) windowFocused=\(windows.map { bool($0, kAXFocusedAttribute) ?? false }) windowMain=\(windows.map { bool($0, kAXMainAttribute) ?? false })"
            let state = "trusted=true pid=\(app.processIdentifier) windows=\(windows.count) \(focus) found=\(found.map(\.message.bubbleText))"
            if debugState(state) {
                for root in roots { dump(root, depth: 0) }
            }
        }

        let keys = Set(found.map(\.key))
        let newOnes = found.filter { !visibleKeys.contains($0.key) }
        visibleKeys = keys

        // Don't replay whatever was already on screen when we started.
        guard primed else { primed = true; return }
        guard !newOnes.isEmpty, newOnes.count <= Constants.historyBurst else { return }

        // The history panel lists old notifications: never say them, and never close them
        // (closing would clear them from history). They're already in visibleKeys, so they
        // won't count as new after the panel closes either.
        if isHistoryPanelOpen(axApp, windows: windows) {
            debugLog("history panel open — ignoring \(newOnes.count) item(s)")
            return
        }

        var emitted = Set<String>()
        for item in newOnes where emitted.insert(item.key).inserted {
            let wantsDismiss = shouldDismissOriginal?(item.message) == true
            if wantsDismiss {
                let closed = dismiss(item.element)
                debugLog("dismiss \(item.message.bubbleText) → \(closed ? "closed" : "no close action found")")
            } else {
                debugLog("keep banner \(item.message.bubbleText): no pet will say it")
            }
            onMessage?(item.message)
        }
    }

    private func collect(in element: AXUIElement, depth: Int, into found: inout [Found]) {
        guard depth < Constants.maxDepth else { return }
        let subrole = string(element, kAXSubroleAttribute) ?? ""

        if subrole.hasPrefix("AXNotificationCenter"), subrole != "AXNotificationCenterBannerStack" {
            if let message = parseNotification(element) {
                found.append((key: "\(message.app)|\(message.sender ?? "")|\(message.body)", message: message, element: element))
            }
            return
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            collect(in: child, depth: depth + 1, into: &found)
        }
    }

    /// The history panel is opened by a click, so it takes keyboard focus; banners never do.
    /// (On macOS 26 banners live in a full-screen window, so window size can't tell them apart.)
    private func isHistoryPanelOpen(_ axApp: AXUIElement, windows: [AXUIElement]) -> Bool {
        if element(axApp, kAXFocusedWindowAttribute) != nil { return true }
        return windows.contains { bool($0, kAXFocusedAttribute) == true || bool($0, kAXMainAttribute) == true }
    }

    // MARK: - Closing the original banner

    /// Close only — never AXPress the banner itself, that opens the sending app.
    private func dismiss(_ notification: AXUIElement) -> Bool {
        if let action = actionNames(of: notification).first(where: Self.isCloseAction) {
            return AXUIElementPerformAction(notification, action as CFString) == .success
        }
        if let button = findCloseButton(in: notification, depth: 0) {
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        }
        return false
    }

    /// Custom AX actions look like "Name:Close\nTarget:0x0\nSelector:(null)".
    private static func isCloseAction(_ action: String) -> Bool {
        let lowered = action.lowercased()
        return lowered.contains("name:close") || lowered.contains("name:닫기") || action == "AXCancel"
    }

    private func findCloseButton(in element: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth < Constants.maxDepth else { return nil }
        if string(element, kAXRoleAttribute) == (kAXButtonRole as String) {
            let subrole = string(element, kAXSubroleAttribute) ?? ""
            let label = [kAXDescriptionAttribute, kAXTitleAttribute, kAXIdentifierAttribute]
                .compactMap { string(element, $0)?.lowercased() }
                .joined(separator: " ")
            if subrole == (kAXCloseButtonSubrole as String) || label.contains("close") || label.contains("닫기") {
                return element
            }
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            if let button = findCloseButton(in: child, depth: depth + 1) { return button }
        }
        return nil
    }

    // MARK: - Parsing

    private func parseNotification(_ element: AXUIElement) -> PetMessage? {
        var texts: [String] = []
        gatherTexts(element, depth: 0, into: &texts)
        texts = texts.filter { !$0.isEmpty }
        guard let body = texts.last else { return nil }

        let sender = texts.count >= 2 ? texts[0] : nil
        let app = appName(for: element, texts: texts) ?? Constants.fallbackApp
        return PetMessage(app: app, body: body, sender: sender)
    }

    private func gatherTexts(_ element: AXUIElement, depth: Int, into texts: inout [String]) {
        guard depth < Constants.maxDepth else { return }
        if string(element, kAXRoleAttribute) == (kAXStaticTextRole as String),
           let value = string(element, kAXValueAttribute).map(Self.clean) {
            texts.append(value)
        }
        for child in children(of: element, attribute: kAXChildrenAttribute) {
            gatherTexts(child, depth: depth + 1, into: &texts)
        }
    }

    /// 1) "bundleIdentifier=com.kakao.KakaoTalkMac,…" in AXStackingIdentifier → app's name
    /// 2) AXDescription. macOS 26: "<앱> <제목>, <본문>" (e.g. "카카오톡 손범수, 집가고싶어ㅠㅠ"),
    ///    older: "<앱>, <제목>, <본문>". Take the first comma part and strip the title from its end.
    private func appName(for element: AXUIElement, texts: [String]) -> String? {
        if let stacking = string(element, "AXStackingIdentifier"),
           let bundleID = stacking.components(separatedBy: ",")
               .first(where: { $0.hasPrefix("bundleIdentifier=") })?
               .replacingOccurrences(of: "bundleIdentifier=", with: ""),
           let name = Self.name(forBundleID: bundleID) {
            return name
        }
        if let description = string(element, kAXDescriptionAttribute).map(Self.clean) {
            // Titles can contain ", " themselves (Discord: "닉네임 (일반, 음성 채널)"),
            // so cut at the title instead of at the first comma.
            if texts.count >= 2, let range = description.range(of: " " + texts[0]) {
                let app = description[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if !app.isEmpty { return app }
            }
            let first = description.components(separatedBy: ", ").first?.trimmingCharacters(in: .whitespaces) ?? ""
            if !first.isEmpty, !texts.contains(first) { return first }
        }
        return nil
    }

    /// Drop the invisible bidi isolate marks (U+2066…U+2069) macOS wraps names in.
    private static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func name(forBundleID bundleID: String) -> String? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - AX helpers

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func children(of element: AXUIElement, attribute: String) -> [AXUIElement] {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return (value as? NSNumber)?.boolValue
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
        return names as? [String] ?? []
    }

    private func size(of element: AXUIElement) -> CGSize? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    // MARK: - Debug log (~/Library/Logs/NotiPet/ax.log)

    /// Logs `state` only when it changed since last time. Returns true if it was logged.
    @discardableResult
    private func debugState(_ state: String) -> Bool {
        guard debug, state != lastDebugState else { return false }
        lastDebugState = state
        debugLog("── " + state)
        return true
    }

    private func debugLog(_ line: String) {
        guard debug else { return }
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotiPet")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("ax.log")
        let stamp = ISO8601DateFormatter().string(from: Date())
        let data = Data("[\(stamp)] \(line)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    private func dump(_ element: AXUIElement, depth: Int) {
        guard depth < Constants.maxDepth else { return }
        let line = [kAXRoleAttribute, kAXSubroleAttribute, kAXValueAttribute, kAXDescriptionAttribute, "AXStackingIdentifier"]
            .map { "\($0)=\(string(element, $0) ?? "")" }
            .joined(separator: " ")
        let actions = actionNames(of: element)
        debugLog(String(repeating: "  ", count: depth) + line
                 + (actions.isEmpty ? "" : " actions=\(actions.map { $0.replacingOccurrences(of: "\n", with: " ") })"))
        for child in children(of: element, attribute: kAXChildrenAttribute) { dump(child, depth: depth + 1) }
    }
}
