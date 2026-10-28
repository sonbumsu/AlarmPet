// LegacyMigration.swift
// The app used to be called AlarmPet (com.sonbumsu.alarmpet). On the first NotiPet launch,
// copy its settings and data over so pets, alarms, sounds and the Klipy key carry on.
// The old files are left in place (copy, not move) in case someone goes back.
// Must run before anything reads UserDefaults or Application Support (see main.swift).

import Foundation

enum LegacyMigration {

    private enum Constants {
        static let oldBundleID = "com.sonbumsu.alarmpet"
        static let oldDirectoryName = "AlarmPet"
        static let newDirectoryName = "NotiPet"
    }

    static func run(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        migrateDefaults(defaults)
        migrateAppSupport(fileManager)
    }

    /// UserDefaults: notification settings, Klipy key, …
    private static func migrateDefaults(_ defaults: UserDefaults) {
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID != Constants.oldBundleID,
              defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
              let old = defaults.persistentDomain(forName: Constants.oldBundleID), !old.isEmpty else { return }
        defaults.setPersistentDomain(old, forName: bundleID)
    }

    /// ~/Library/Application Support/AlarmPet → NotiPet (pets.plist, Sounds/).
    private static func migrateAppSupport(_ fileManager: FileManager) {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let old = appSupport.appendingPathComponent(Constants.oldDirectoryName, isDirectory: true)
        let new = appSupport.appendingPathComponent(Constants.newDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return }
        do {
            try fileManager.copyItem(at: old, to: new)
        } catch {
            NSLog("LegacyMigration: failed to copy %@: %@", old.path, String(describing: error))
        }
    }
}
