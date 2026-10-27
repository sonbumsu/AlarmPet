// AppDirectory.swift
// Knows every name an installed app goes by, so "KakaoTalk", "카카오톡" and "kakaotalk"
// all mean the same app in filters and icon lookups.
// Built lazily on first use from the usual app folders plus running apps.

import AppKit

enum AppDirectory {

    private struct Entry {
        let url: URL
        let names: Set<String>   // original spelling
    }

    private static var index: [String: Entry]?   // lowercased name → entry

    /// All known names of the app called `name` (including `name` itself).
    static func names(for name: String) -> Set<String> {
        entry(for: name)?.names.union([name]) ?? [name]
    }

    static func url(for name: String) -> URL? {
        entry(for: name)?.url
    }

    // MARK: - Index

    private static func entry(for name: String) -> Entry? {
        let key = name.lowercased()
        if let hit = loadedIndex()[key] { return hit }
        // Apps launched after the index was built.
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName?.lowercased() == key
        }), let url = running.bundleURL {
            let entry = makeEntry(url: url, extra: running.localizedName)
            entry.names.forEach { index?[$0.lowercased()] = entry }
            return entry
        }
        return nil
    }

    private static func loadedIndex() -> [String: Entry] {
        if let index { return index }
        var built: [String: Entry] = [:]
        let folders = ["/Applications", "/Applications/Utilities",
                       "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        var urls: [URL] = folders.flatMap { folder -> [URL] in
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return contents.filter { $0.hasSuffix(".app") }.map { URL(fileURLWithPath: folder).appendingPathComponent($0) }
        }
        urls += NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)

        // One entry per app bundle (running apps repeat installed ones).
        var seen = Set<String>()
        for url in urls where seen.insert(url.standardizedFileURL.path).inserted {
            let entry = makeEntry(url: url, extra: nil)
            for name in entry.names where built[name.lowercased()] == nil {
                built[name.lowercased()] = entry
            }
        }
        index = built
        return built
    }

    private static func makeEntry(url: URL, extra: String?) -> Entry {
        var names: Set<String> = [url.deletingPathExtension().lastPathComponent]
        names.insert(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
        if let extra { names.insert(extra) }
        if let bundle = Bundle(url: url) {
            var tables = [bundle.infoDictionary, bundle.localizedInfoDictionary].compactMap { $0 }
            tables += localizedInfoTables(bundle)
            for info in tables {
                for key in ["CFBundleName", "CFBundleDisplayName"] {
                    if let value = info[key] as? String, !value.isEmpty { names.insert(value) }
                }
            }
        }
        return Entry(url: url, names: names)
    }

    /// The user's languages + English, as bare codes ("ko-KR" → "ko").
    private static let languages: Set<String> = {
        Set((Locale.preferredLanguages + ["en"]).map { languageCode($0) })
    }()

    private static func languageCode(_ identifier: String) -> String {
        String(identifier.prefix { $0 != "-" && $0 != "_" }).lowercased()
    }

    /// Localized Info.plist values, read directly so they don't depend on this process's language:
    /// third-party apps use <lang>.lproj/InfoPlist.strings, system apps use InfoPlist.loctable.
    private static func localizedInfoTables(_ bundle: Bundle) -> [[String: Any]] {
        var tables: [[String: Any]] = []
        for localization in bundle.localizations where languages.contains(languageCode(localization)) {
            if let path = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: localization),
               let table = NSDictionary(contentsOfFile: path) as? [String: Any] {
                tables.append(table)
            }
        }
        if let path = bundle.path(forResource: "InfoPlist", ofType: "loctable"),
           let loctable = NSDictionary(contentsOfFile: path) as? [String: Any] {
            for (localization, value) in loctable where languages.contains(languageCode(localization)) {
                if let table = value as? [String: Any] { tables.append(table) }
            }
        }
        return tables
    }
}
