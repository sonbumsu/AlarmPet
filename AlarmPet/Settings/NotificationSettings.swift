// NotificationSettings.swift
// App-wide notification settings: master switch, app name aliases, sources.
// Bubble look / sound / app filters are per pet (see AppSettings).
// Persisted in UserDefaults; observable so SwiftUI updates live.

import Foundation
import Combine

final class NotificationSettings: ObservableObject {

    static let shared = NotificationSettings()

    private let defaults: UserDefaults

    // MARK: - Bubble
    /// Master switch: pause every pet's bubbles.
    @Published var bubbleEnabled: Bool     { didSet { save(bubbleEnabled, "bubbleEnabled") } }

    // MARK: - App names
    /// One "원래이름=표시이름" per line.
    @Published var appAliases: String      { didSet { save(appAliases, "appAliases") } }

    // MARK: - Sources
    @Published var localServerEnabled: Bool { didSet { save(localServerEnabled, "localServerEnabled") } }
    @Published var localServerPort: Int     { didSet { save(localServerPort, "localServerPort") } }
    /// Why the local server isn't listening (shown in the panel). Not saved.
    @Published var localServerError: String?
    @Published var systemNotificationsEnabled: Bool { didSet { save(systemNotificationsEnabled, "systemNotificationsEnabled") } }
    /// Close the original macOS banner when the pet says it instead.
    @Published var hideOriginalBanners: Bool { didSet { save(hideOriginalBanners, "hideOriginalBanners") } }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "bubbleEnabled": true,
            "appAliases": "KakaoTalk=카카오톡\nSlack=슬랙\nMessages=메시지",
            "localServerEnabled": true,
            "localServerPort": 7777,
            "systemNotificationsEnabled": false,
            "hideOriginalBanners": true,
        ])
        bubbleEnabled = defaults.bool(forKey: "bubbleEnabled")
        appAliases = defaults.string(forKey: "appAliases") ?? ""
        localServerEnabled = defaults.bool(forKey: "localServerEnabled")
        localServerPort = defaults.integer(forKey: "localServerPort")
        systemNotificationsEnabled = defaults.bool(forKey: "systemNotificationsEnabled")
        hideOriginalBanners = defaults.bool(forKey: "hideOriginalBanners")
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }

    // MARK: - Helpers

    /// "KakaoTalk" → "카카오톡" using the alias table.
    func displayName(for app: String) -> String {
        for line in appAliases.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0].caseInsensitiveCompare(app) == .orderedSame, !parts[1].isEmpty {
                return parts[1]
            }
        }
        return app
    }
}
