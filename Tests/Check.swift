// Check.swift
// Tiny test helpers (no XCTest needed — Command Line Tools are enough). Run with ./test.sh.

import Foundation

enum Check {
    static var passed = 0
    static var failed: [String] = []

    static func section(_ name: String) {
        print("\n── \(name)")
    }

    static func that(_ ok: Bool, _ name: String, file: String = #fileID, line: Int = #line) {
        if ok {
            passed += 1
            print("  ✓ \(name)")
        } else {
            failed.append("\(name)  (\(file):\(line))")
            print("  ✗ \(name)  (\(file):\(line))")
        }
    }

    /// Keep the main run loop turning until `done` or the timeout (for async code on the main queue).
    static func wait(seconds: TimeInterval, until done: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

/// Fixed dates so tests don't depend on today. 2026-10-27 is a Tuesday.
func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
    Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi, second: s))!
}

/// A pet record as it was saved by an older version (before speech, reminder fields existed
/// and while flip settings still did).
func legacyRecord(extra: [String: Any] = [:]) -> PetRecord {
    var dict: [String: Any] = [
        "instanceID": "pet-1", "positionX": 1.0, "positionY": 2.0, "scale": 1.2, "rotation": 0.0,
        "opacity": 1.0, "speed": 1.0, "clickThrough": false, "lockPosition": false, "alwaysOnTop": true,
        "playing": true, "label": "kurukuru", "flipHorizontal": true, "flipVertical": false,
    ]
    dict.merge(extra) { _, new in new }
    let data = try! PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    return try! PropertyListDecoder().decode(PetRecord.self, from: data)
}
