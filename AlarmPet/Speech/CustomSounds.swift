// CustomSounds.swift
// The user's own sound files ("내 소리"), usable as a notification sound or an alarm.
// Imported files are copied to ~/Library/Application Support/AlarmPet/Sounds,
// so moving or deleting the original doesn't break the setting.
// In settings they are stored as "내소리:<file name>".

import AppKit
import UniformTypeIdentifiers

final class CustomSounds: ObservableObject {

    static let shared = CustomSounds()
    static let prefix = "내소리:"

    /// Sound names ("내소리:…"), sorted by file name.
    @Published private(set) var names: [String] = []

    let directory: URL

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlarmPet/Sounds", isDirectory: true)) {
        self.directory = directory
        reload()
    }

    // MARK: - Names

    static func isCustom(_ name: String) -> Bool { name.hasPrefix(prefix) }

    /// "내소리:카톡왔숑.mp3" → "카톡왔숑"; other names are returned as they are.
    static func displayName(_ name: String) -> String {
        guard isCustom(name) else { return name }
        return (String(name.dropFirst(prefix.count)) as NSString).deletingPathExtension
    }

    func url(for name: String) -> URL? {
        guard Self.isCustom(name) else { return nil }
        let file = String(name.dropFirst(Self.prefix.count))
        guard !file.isEmpty, !file.contains("/") else { return nil }
        return directory.appendingPathComponent(file)
    }

    /// nil when it isn't a custom sound or the file is gone / unreadable.
    func makeSound(_ name: String) -> NSSound? {
        url(for: name).flatMap { NSSound(contentsOf: $0, byReference: true) }
    }

    // MARK: - Import / remove

    /// Copies an audio file into the library and returns its sound name.
    @discardableResult
    func importFile(_ source: URL) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var file = source.lastPathComponent
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(file).path) {
            file = "\(base) \(counter)" + (ext.isEmpty ? "" : ".\(ext)")
            counter += 1
        }
        try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(file))
        reload()
        return Self.prefix + file
    }

    func remove(_ name: String) {
        guard let url = url(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
        reload()
    }

    /// Asks for an audio file and imports it. nil if cancelled or the file can't be played.
    func pickAndImport() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        panel.message = "알림·알람 소리로 쓸 음성 파일을 골라 주세요 (mp3, m4a, wav, aiff …)"
        panel.prompt = "추가"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        guard NSSound(contentsOf: url, byReference: true) != nil else {
            let alert = NSAlert()
            alert.messageText = "이 파일은 재생할 수 없어요"
            alert.informativeText = "mp3, m4a, wav, aiff 같은 음성 파일을 골라 주세요."
            alert.runModal()
            return nil
        }
        do {
            return try importFile(url)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return nil
        }
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                                  options: .skipsHiddenFiles)) ?? []
        names = files
            .map { Self.prefix + $0.lastPathComponent }
            .sorted { Self.displayName($0).localizedStandardCompare(Self.displayName($1)) == .orderedAscending }
    }
}
