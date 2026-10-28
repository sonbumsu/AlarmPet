// ReminderTests.swift
// When reminders ring, snoozes, editing, and how they're saved.

import Foundation

func reminderTests() {
    Check.section("알람: 울리는 시각")
    let tue0700 = date(2026, 10, 27, 7, 0)
    Check.that(Calendar.current.component(.weekday, from: tue0700) == 3, "fixture: 2026-10-27 is Tuesday")

    let weekdays = PetReminder(title: "일어나기", hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6])
    Check.that(weekdays.nextOccurrence(after: tue0700) == date(2026, 10, 27, 7, 30), "평일 7:30 → same Tuesday 7:30")
    Check.that(weekdays.nextOccurrence(after: date(2026, 10, 30, 8, 0)) == date(2026, 11, 2, 7, 30), "after Fri 8:00 → next Monday")

    var off = weekdays
    off.enabled = false
    Check.that(off.nextOccurrence(after: tue0700) == nil, "switched off → never rings")

    let once = PetReminder.once(title: "약", hour: 6, minute: 0, now: tue0700)
    Check.that(once.onceDate == date(2026, 10, 28, 6, 0), "once 06:00 made at 07:00 → tomorrow")
    Check.that(once.nextOccurrence(after: date(2026, 10, 28, 6, 0)) == nil, "once rings only once")
    Check.that(PetReminder.once(title: "", hour: 21, minute: 15, now: tue0700).onceDate == date(2026, 10, 27, 21, 15),
               "once 21:15 made at 07:00 → today")

    let five = PetReminder.inMinutes(5, title: "x", now: date(2026, 10, 27, 23, 58, 30))
    Check.that(five.onceDate == date(2026, 10, 28, 0, 3, 30) && five.hour == 0 && five.minute == 3, "5분 뒤 across midnight")

    Check.section("알람: 표시")
    Check.that(weekdays.repeatText == "평일", "평일")
    Check.that(PetReminder(title: "", hour: 9, minute: 0, weekdays: Array(1...7)).repeatText == "매일", "매일")
    Check.that(PetReminder(title: "", hour: 9, minute: 0, weekdays: [1, 7]).repeatText == "주말", "주말")
    Check.that(PetReminder(title: "", hour: 9, minute: 0, weekdays: [2, 4, 6]).repeatText == "월·수·금", "월·수·금")
    Check.that(PetReminder(title: "", hour: 7, minute: 5).timeText == "07:05", "timeText 07:05")

    Check.section("알람: 5분 뒤 다시")
    var snoozed = weekdays
    snoozed.snoozeUntil = date(2026, 10, 27, 7, 5)
    Check.that(snoozed.nextOccurrence(after: tue0700) == date(2026, 10, 27, 7, 5), "snooze before the regular time rings first")
    Check.that(snoozed.nextOccurrence(after: date(2026, 10, 27, 7, 5)) == date(2026, 10, 27, 7, 30), "after the snooze, back to the schedule")

    var rangOnce = once
    rangOnce.enabled = false                         // a one-time reminder turns itself off when it rings…
    rangOnce.snoozeUntil = date(2026, 10, 28, 6, 5)  // …and can still be snoozed
    Check.that(rangOnce.nextOccurrence(after: date(2026, 10, 28, 6, 0)) == date(2026, 10, 28, 6, 5), "snooze works on a rung one-time reminder")

    let settings = AppSettings(record: legacyRecord())
    settings.addReminder(weekdays)
    Check.that(settings.snoozeReminder(id: weekdays.id, until: date(2026, 10, 27, 7, 5)), "snooze saved on the pet")
    Check.that(settings.reminders.first?.snoozeUntil == date(2026, 10, 27, 7, 5), "snooze stored in the reminder")
    Check.that(!settings.snoozeReminder(id: UUID(), until: Date()), "snooze of an unknown reminder (test alarm) → false")
    settings.setReminder(id: weekdays.id, enabled: false)
    Check.that(settings.reminders.first?.snoozeUntil == nil, "switching off cancels the snooze")
    settings.snoozeReminder(id: weekdays.id, until: Date())
    settings.clearSnooze(id: weekdays.id)
    Check.that(settings.reminders.first?.snoozeUntil == nil, "clearSnooze")

    Check.section("알람: 목록 / 수정")
    let list = AppSettings(record: legacyRecord())
    list.addReminder(PetReminder(title: "b", hour: 9, minute: 0, weekdays: [2]))
    list.addReminder(PetReminder(title: "a", hour: 7, minute: 5, weekdays: [2]))
    Check.that(list.reminders.map(\.title) == ["a", "b"], "list sorted by time")

    var edited = list.reminders[1]          // "b" 09:00
    edited.title = "b2"
    edited.hour = 6
    list.updateReminder(edited)
    Check.that(list.reminders.map(\.title) == ["b2", "a"] && list.reminders[0].id == edited.id, "edit keeps id, re-sorts")
    list.removeReminder(id: edited.id)
    Check.that(list.reminders.map(\.title) == ["a"], "remove")

    var past = PetReminder.once(title: "past", hour: 1, minute: 0, now: date(2020, 1, 1, 0, 0))
    past.enabled = false
    list.addReminder(past)
    list.setReminder(id: past.id, enabled: true)
    let revived = list.reminders.first { $0.id == past.id }!
    Check.that(revived.enabled && (revived.onceDate ?? .distantPast) > Date(), "re-enabling a rung one-time reminder → its next time")

    Check.section("알람: 저장")
    var record = legacyRecord()
    Check.that(record.reminders.isEmpty && record.alarmSoundName == AlarmSound.defaultName, "old record → no reminders, default alarm sound")
    record.reminders = [weekdays, snoozed, once]
    let roundTrip = try! PropertyListDecoder().decode(PetRecord.self, from: PropertyListEncoder().encode(record))
    Check.that(roundTrip.reminders == record.reminders, "reminders (incl. snooze) round-trip")

    let oldReminder: [String: Any] = ["id": UUID().uuidString, "title": "옛날", "hour": 8, "minute": 0,
                                      "weekdays": [2], "enabled": true]
    let withOld = legacyRecord(extra: ["reminders": [oldReminder]])
    Check.that(withOld.reminders.first?.title == "옛날" && withOld.reminders.first?.snoozeUntil == nil,
               "reminder saved before snooze existed still loads")
}
