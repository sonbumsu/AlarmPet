// PetReminder.swift
// One alarm-style reminder belonging to a pet: "07:30 평일 — 일어나기".

import Foundation

struct PetReminder: Codable, Equatable, Identifiable {
    var id = UUID()
    var title: String
    var hour: Int
    var minute: Int
    /// Calendar weekdays (1 = 일 … 7 = 토). Empty = rings once, at `onceDate`.
    var weekdays: [Int] = []
    var onceDate: Date?
    var enabled: Bool = true
    /// Set by [5분 뒤 다시]: rings once more at this time, then clears. Saved, so it survives a restart.
    var snoozeUntil: Date? = nil

    var isOnce: Bool { weekdays.isEmpty }

    /// One-time reminder at the next `hour:minute` (today if still ahead, else tomorrow).
    static func once(title: String, hour: Int, minute: Int, now: Date = Date()) -> PetReminder {
        let calendar = Calendar.current
        let fire = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                     matchingPolicy: .nextTime) ?? now
        return PetReminder(title: title, hour: hour, minute: minute, onceDate: fire)
    }

    /// One-time reminder `minutes` from now ("5분 뒤").
    static func inMinutes(_ minutes: Int, title: String, now: Date = Date()) -> PetReminder {
        let fire = now.addingTimeInterval(TimeInterval(minutes * 60))
        let parts = Calendar.current.dateComponents([.hour, .minute], from: fire)
        return PetReminder(title: title, hour: parts.hour ?? 0, minute: parts.minute ?? 0, onceDate: fire)
    }

    /// First time this reminder rings strictly after `date` (nil = never again).
    /// A pending snooze counts even if the reminder itself is already switched off (a one-time
    /// reminder turns itself off when it rings, and may then be snoozed).
    func nextOccurrence(after date: Date) -> Date? {
        var candidates: [Date] = []
        if let snoozeUntil, snoozeUntil > date { candidates.append(snoozeUntil) }
        guard enabled else { return candidates.min() }

        if isOnce {
            if let onceDate, onceDate > date { candidates.append(onceDate) }
        } else {
            let calendar = Calendar.current
            candidates += weekdays.compactMap { weekday in
                calendar.nextDate(after: date,
                                  matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
                                  matchingPolicy: .nextTime)
            }
        }
        return candidates.min()
    }

    // MARK: - Display

    var timeText: String { String(format: "%02d:%02d", hour, minute) }

    /// "매일", "평일", "주말", "월·수·금", or "한 번 (10/27)".
    var repeatText: String {
        let set = Set(weekdays)
        switch set {
        case Set(1...7): return "매일"
        case [2, 3, 4, 5, 6]: return "평일"
        case [1, 7]: return "주말"
        case []:
            guard let onceDate else { return "한 번" }
            let formatter = DateFormatter()
            formatter.dateFormat = "M/d"
            return "한 번 (\(formatter.string(from: onceDate)))"
        default:
            return Self.weekdayOrder.filter(set.contains).map { Self.weekdayName[$0] ?? "" }.joined(separator: "·")
        }
    }

    /// Monday-first display order.
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static let weekdayName = [1: "일", 2: "월", 3: "화", 4: "수", 5: "목", 6: "금", 7: "토"]
}
