// PetsStore.swift
// Stores all pets in a single Application Support plist.
// Writes are debounced so dragging a slider / resize handle doesn't hit the disk every frame.

import Foundation

struct PetRecord: Codable, Equatable {
    let instanceID: String
    var positionX: Double      // pet center, screen coordinates
    var positionY: Double
    var scale: Double
    var rotation: Double       // degrees, clockwise
    var opacity: Double
    var speed: Double
    var clickThrough: Bool
    var lockPosition: Bool
    var alwaysOnTop: Bool
    var playing: Bool
    var label: String
    var assetBookmark: Data?

    // Speech (per pet)
    var speaksNotifications: Bool
    var bubbleDuration: Double
    var bubbleSize: Double
    var soundName: String
    var soundVolume: Double
    var ttsEnabled: Bool
    var bounceWhileTalking: Bool
    var allowedApps: String     // comma separated, empty = every app
    var blockedApps: String     // comma separated

    // Reminders (per pet)
    var reminders: [PetReminder]
    var alarmSoundName: String
    var alarmVolume: Double

    static func `default`(instanceID: String, index: Int) -> PetRecord {
        let offset = Double((index - 1) * 60)
        return PetRecord(
            instanceID: instanceID,
            positionX: 400.0 + offset,
            positionY: 300.0 + offset,
            scale: 1.0,
            rotation: 0.0,
            opacity: 1.0,
            speed: 1.0,
            clickThrough: false,
            lockPosition: false,
            alwaysOnTop: true,
            playing: true,
            label: "펫 \(index)",
            assetBookmark: nil,
            speaksNotifications: SpeechDefaults.speaksNotifications,
            bubbleDuration: SpeechDefaults.bubbleDuration,
            bubbleSize: SpeechDefaults.bubbleSize,
            soundName: SpeechDefaults.soundName,
            soundVolume: SpeechDefaults.soundVolume,
            ttsEnabled: SpeechDefaults.ttsEnabled,
            bounceWhileTalking: SpeechDefaults.bounceWhileTalking,
            allowedApps: SpeechDefaults.allowedApps,
            blockedApps: SpeechDefaults.blockedApps,
            reminders: [],
            alarmSoundName: AlarmSound.defaultName,
            alarmVolume: 0.8
        )
    }
}

extension PetRecord {
    /// Speech and reminder fields were added later: records saved before that get the defaults below.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        instanceID = try c.decode(String.self, forKey: .instanceID)
        positionX = try c.decode(Double.self, forKey: .positionX)
        positionY = try c.decode(Double.self, forKey: .positionY)
        scale = try c.decode(Double.self, forKey: .scale)
        rotation = try c.decode(Double.self, forKey: .rotation)
        opacity = try c.decode(Double.self, forKey: .opacity)
        speed = try c.decode(Double.self, forKey: .speed)
        clickThrough = try c.decode(Bool.self, forKey: .clickThrough)
        lockPosition = try c.decode(Bool.self, forKey: .lockPosition)
        alwaysOnTop = try c.decode(Bool.self, forKey: .alwaysOnTop)
        playing = try c.decode(Bool.self, forKey: .playing)
        label = try c.decode(String.self, forKey: .label)
        assetBookmark = try c.decodeIfPresent(Data.self, forKey: .assetBookmark)

        speaksNotifications = try c.decodeIfPresent(Bool.self, forKey: .speaksNotifications) ?? SpeechDefaults.speaksNotifications
        bubbleDuration = try c.decodeIfPresent(Double.self, forKey: .bubbleDuration) ?? SpeechDefaults.bubbleDuration
        bubbleSize = try c.decodeIfPresent(Double.self, forKey: .bubbleSize) ?? SpeechDefaults.bubbleSize
        soundName = try c.decodeIfPresent(String.self, forKey: .soundName) ?? SpeechDefaults.soundName
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? SpeechDefaults.soundVolume
        ttsEnabled = try c.decodeIfPresent(Bool.self, forKey: .ttsEnabled) ?? SpeechDefaults.ttsEnabled
        bounceWhileTalking = try c.decodeIfPresent(Bool.self, forKey: .bounceWhileTalking) ?? SpeechDefaults.bounceWhileTalking
        allowedApps = try c.decodeIfPresent(String.self, forKey: .allowedApps) ?? SpeechDefaults.allowedApps
        blockedApps = try c.decodeIfPresent(String.self, forKey: .blockedApps) ?? SpeechDefaults.blockedApps

        reminders = try c.decodeIfPresent([PetReminder].self, forKey: .reminders) ?? []
        alarmSoundName = try c.decodeIfPresent(String.self, forKey: .alarmSoundName) ?? AlarmSound.defaultName
        alarmVolume = try c.decodeIfPresent(Double.self, forKey: .alarmVolume) ?? 0.8
    }
}

/// Defaults for a pet's speech settings. These used to be app-wide UserDefaults,
/// so whatever the user picked there carries over to every pet.
enum SpeechDefaults {
    private static let defaults = UserDefaults.standard

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }
    private static func double(_ key: String, _ fallback: Double) -> Double {
        defaults.object(forKey: key) == nil ? fallback : defaults.double(forKey: key)
    }
    private static func string(_ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    static var speaksNotifications: Bool { true }
    static var bubbleDuration: Double { double("displayDuration", 5) }
    static var bubbleSize: Double { double("bubbleSize", 1) }
    static var soundName: String { string("soundName", "뿅") }
    static var soundVolume: Double { double("soundVolume", 0.6) }
    static var ttsEnabled: Bool { bool("ttsEnabled", false) }
    static var bounceWhileTalking: Bool { bool("bounceWhileTalking", true) }
    static var allowedApps: String { string("allowedApps", "") }
    static var blockedApps: String { string("blockedApps", "") }
}

private struct PetsManifest: Codable {
    var schemaVersion: Int
    var nextPetIndex: Int
    var pets: [PetRecord]
}

final class PetsStore {

    // MARK: - Constants

    private enum Constants {
        static let schemaVersion = 1
        static let directoryName = "AlarmPet"
        static let fileName = "pets.plist"
        static let saveDelay: TimeInterval = 0.4
    }

    // MARK: - Dependencies

    private let fileManager: FileManager
    private let storeURL: URL

    // MARK: - State

    private var manifest = PetsManifest(schemaVersion: Constants.schemaVersion, nextPetIndex: 1, pets: [])
    private var pendingSave: DispatchWorkItem?

    // MARK: - Init

    init(fileManager: FileManager = .default, storeURL: URL? = nil) {
        self.fileManager = fileManager
        self.storeURL = storeURL ?? PetsStore.defaultStoreURL(fileManager: fileManager)
    }

    // MARK: - Public

    var fileURL: URL { storeURL }

    @discardableResult
    func loadRecords() -> [PetRecord] {
        if fileManager.fileExists(atPath: storeURL.path), let loaded = loadManifestFromDisk() {
            manifest = loaded
        } else {
            manifest = PetsManifest(schemaVersion: Constants.schemaVersion, nextPetIndex: 1, pets: [])
            saveManifest()
        }
        return manifest.pets
    }

    func makeNewPetRecord() -> PetRecord {
        let index = manifest.nextPetIndex
        manifest.nextPetIndex += 1
        scheduleSave()
        return .default(instanceID: "pet-\(index)", index: index)
    }

    func upsert(_ record: PetRecord) {
        if let index = manifest.pets.firstIndex(where: { $0.instanceID == record.instanceID }) {
            manifest.pets[index] = record
        } else {
            manifest.pets.append(record)
        }
        scheduleSave()
    }

    func remove(instanceID: String) {
        manifest.pets.removeAll { $0.instanceID == instanceID }
        scheduleSave()
    }

    /// Write any pending change immediately (call on quit).
    func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        saveManifest()
    }

    // MARK: - Disk I/O

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.saveManifest()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.saveDelay, execute: work)
    }

    private func loadManifestFromDisk() -> PetsManifest? {
        do {
            let data = try Data(contentsOf: storeURL)
            return try PropertyListDecoder().decode(PetsManifest.self, from: data)
        } catch {
            backupCorruptedStore()
            NSLog("PetsStore: failed to decode plist at %@: %@", storeURL.path, String(describing: error))
            return nil
        }
    }

    private func saveManifest() {
        do {
            try fileManager.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListEncoder().encode(manifest)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            NSLog("PetsStore: failed to save plist at %@: %@", storeURL.path, String(describing: error))
        }
    }

    private func backupCorruptedStore() {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupURL = storeURL.deletingPathExtension().appendingPathExtension("corrupted-\(timestamp).plist")

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: storeURL, to: backupURL)
        } catch {
            NSLog("PetsStore: failed to back up corrupted plist: %@", String(describing: error))
        }
    }

    // MARK: - Paths

    private static func defaultStoreURL(fileManager: FileManager) -> URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        return appSupportURL
            .appendingPathComponent(Constants.directoryName, isDirectory: true)
            .appendingPathComponent(Constants.fileName)
    }
}
