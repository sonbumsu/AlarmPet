// main.swift — test runner. Run with ./test.sh

import Foundation

reminderTests()
notificationTests()

print("\n\(Check.passed) passed, \(Check.failed.count) failed")
if !Check.failed.isEmpty {
    Check.failed.forEach { print("  ✗ \($0)") }
    exit(1)
}
