// SettingsView.swift
// Per-pet settings panel: "펫" tab (look & behavior), "알림" tab (this pet's speech bubble,
// sound, and which apps it talks about), and "리마인더" tab (this pet's alarms).

import SwiftUI
import ServiceManagement

/// Which tab the settings panel shows (lets the menu bar open straight to "리마인더").
final class SettingsTabs: ObservableObject {
    enum Tab: Int { case pet, speech, reminders }
    @Published var selected: Tab = .pet
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var tabs: SettingsTabs
    var onImport: () -> Void
    var onUseDefaultPet: () -> Void
    var onRemove: () -> Void
    var onQuit: () -> Void
    var onTestBubble: () -> Void
    var onTestAlarm: () -> Void

    @StateObject private var draft = ReminderDraft()
    @ObservedObject private var customSounds = CustomSounds.shared

    var body: some View {
        TabView(selection: $tabs.selected) {
            ScrollView { petTab.padding(16) }
                .tabItem { Text("펫") }
                .tag(SettingsTabs.Tab.pet)
            ScrollView { speechTab.padding(16) }
                .tabItem { Text("알림") }
                .tag(SettingsTabs.Tab.speech)
            ScrollView { reminderTab.padding(16) }
                .tabItem { Text("리마인더") }
                .tag(SettingsTabs.Tab.reminders)
        }
        .padding(.top, 8)
        .frame(width: 320, height: 600)
    }

    // MARK: - 펫 tab

    private var petTab: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                TextField("이름", text: $settings.label)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                Spacer()
                Button("파일 바꾸기…", action: onImport)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("기본 펫으로 바꾸기", action: onUseDefaultPet)
                    .controlSize(.small)
                    .disabled(settings.assetBookmark == nil)
                    .help("알람시계 고양이로 되돌려요. 다른 설정은 그대로예요.")
            }

            Divider()

            // ── Playback ─────────────────────────────────────────────────
            SectionHeader("재생")

            Toggle("재생 중", isOn: $settings.playing)

            LabeledSlider(label: "속도",
                          value: $settings.speed,
                          range: 0.1...4.0,
                          format: "%.1fx")

            Divider()

            // ── Appearance ────────────────────────────────────────────────
            SectionHeader("모양")

            LabeledSlider(label: "투명도",
                          value: $settings.opacity,
                          range: 0.1...1.0,
                          format: "%.0f%%",
                          displayMultiplier: 100)

            EditableSlider(label: "크기",
                           value: $settings.scale,
                           range: 0.1...8.0,
                           unit: "%",
                           displayMultiplier: 100,
                           resetValue: 1.0)

            EditableSlider(label: "각도",
                           value: $settings.rotation,
                           range: -180...180,
                           unit: "°",
                           resetValue: 0)

            Text("⌥ Option 누른 채 펫에 올리면 크기·회전 핸들이 나와요")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            // ── Behavior ─────────────────────────────────────────────────
            SectionHeader("동작")

            Toggle("항상 위에",  isOn: $settings.alwaysOnTop)
            Toggle("클릭 통과",  isOn: $settings.clickThrough)
            Toggle("위치·크기 잠금",  isOn: $settings.lockPosition)

            Divider()

            // ── System ────────────────────────────────────────────────────
            StartAtLoginToggle()

            Divider()

            // ── Bottom buttons ────────────────────────────────────────────
            HStack {
                Button(role: .destructive, action: onRemove) {
                    Label("펫 삭제", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
                Spacer()
                Button("종료", action: onQuit)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - 알림 tab

    private var speechTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("이 펫이 알림 말하기", isOn: $settings.speaksNotifications)

            Group {
                Divider()

                // ── Bubble ────────────────────────────────────────────────
                SectionHeader("말풍선")

                EditableSlider(label: "말풍선 크기",
                               value: $settings.bubbleSize,
                               range: 0.7...2.0,
                               unit: "%",
                               displayMultiplier: 100,
                               resetValue: 1.0)

                LabeledSlider(label: "표시 시간",
                              value: $settings.bubbleDuration,
                              range: 2...15,
                              format: "%.0f초",
                              step: 1)

                Toggle("말할 때 통통 튀기", isOn: $settings.bounceWhileTalking)

                Divider()

                // ── Sound ─────────────────────────────────────────────────
                SectionHeader("소리")

                HStack {
                    Picker("알림 소리", selection: $settings.soundName) {
                        Text("없음").tag("")
                        Section("귀여운 소리") {
                            ForEach(PetSound.builtIn, id: \.self) { Text($0).tag($0) }
                        }
                        Section("macOS 기본 소리") {
                            ForEach(PetSound.system, id: \.self) { Text($0).tag($0) }
                        }
                        customSoundSection
                    }
                    Button {
                        PetSound.play(settings.soundName, volume: settings.soundVolume, maxDuration: AlarmSound.previewLimit)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.soundName.isEmpty)
                    .help("미리 듣기")
                }
                .onChange(of: settings.soundName) { _, name in
                    PetSound.play(name, volume: settings.soundVolume, maxDuration: AlarmSound.previewLimit)
                }

                customSoundButtons(selection: $settings.soundName, fallback: PetSound.builtIn[0])

                if !settings.soundName.isEmpty {
                    HStack {
                        Image(systemName: "speaker.fill").font(.caption).foregroundColor(.secondary)
                        Slider(value: $settings.soundVolume, in: 0.05...1)
                        Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundColor(.secondary)
                    }
                }

                Toggle("소리 내서 읽기 (TTS)", isOn: $settings.ttsEnabled)

                Divider()

                // ── Apps ──────────────────────────────────────────────────
                SectionHeader("말할 앱")

                LabeledField(label: "말해줄 앱 (비우면 전체, 쉼표로 구분)", text: $settings.allowedApps, placeholder: "카카오톡, Discord")
                LabeledField(label: "무시할 앱 (쉼표로 구분)", text: $settings.blockedApps, placeholder: "메일")
            }
            .disabled(!settings.speaksNotifications)

            Divider()

            Button("이 펫으로 말풍선 테스트", action: onTestBubble)
                .controlSize(.small)
        }
    }

    // MARK: - 리마인더 tab

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var reminderTab: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── New / edit reminder ───────────────────────────────────────
            SectionHeader(draft.editingID == nil ? "새 리마인더" : "리마인더 수정")

            TextField("할 일 (예: 물 마시기)", text: $draft.title)
                .textFieldStyle(.roundedBorder)

            HStack {
                DatePicker("시간", selection: $draft.time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                Spacer()
                if draft.editingID != nil {
                    Button("취소") { draft.reset() }
                        .controlSize(.small)
                }
                Button(draft.editingID == nil ? "추가" : "저장") {
                    let reminder = draft.makeReminder()
                    if draft.editingID == nil {
                        settings.addReminder(reminder)
                    } else {
                        settings.updateReminder(reminder)
                    }
                    draft.reset()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            HStack(spacing: 4) {
                ForEach(PetReminder.weekdayOrder, id: \.self) { day in
                    Toggle(PetReminder.weekdayName[day] ?? "", isOn: draft.binding(for: day))
                        .toggleStyle(.button)
                        .controlSize(.small)
                }
            }
            Text(draft.weekdays.isEmpty ? "요일을 안 고르면 한 번만 울려요" : "고른 요일마다 울려요")
                .font(.caption2)
                .foregroundColor(.secondary)

            if draft.editingID == nil {
                HStack(spacing: 6) {
                    Text("빠른 추가").font(.caption).foregroundColor(.secondary)
                    ForEach([5, 10, 30, 60], id: \.self) { minutes in
                        Button(minutes < 60 ? "\(minutes)분 뒤" : "1시간 뒤") {
                            settings.addReminder(.inMinutes(minutes, title: draft.titleOrDefault))
                            draft.reset()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // ── List ──────────────────────────────────────────────────────
            SectionHeader("리마인더 목록")

            if settings.reminders.isEmpty {
                Text("아직 없어요")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("누르면 수정할 수 있어요")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ForEach(settings.reminders) { reminder in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { reminder.enabled },
                        set: { settings.setReminder(id: reminder.id, enabled: $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(reminder.timeText)
                                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            Text(reminder.repeatText)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(reminder.title.isEmpty ? "리마인더" : reminder.title)
                                .lineLimit(1)
                            if let snooze = reminder.snoozeUntil, snooze > Date() {
                                Text("💤 \(Self.timeFormatter.string(from: snooze))에 다시 울려요")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { draft.load(reminder) }

                    Button {
                        if draft.editingID == reminder.id { draft.reset() }
                        settings.removeReminder(id: reminder.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("삭제")
                }
                .opacity(reminder.enabled || reminder.snoozeUntil != nil ? 1 : 0.45)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(draft.editingID == reminder.id ? Color.accentColor.opacity(0.15) : Color.clear)
                )
            }

            Divider()

            // ── Alarm sound ───────────────────────────────────────────────
            SectionHeader("알람 소리")

            HStack {
                Picker("알람 소리", selection: $settings.alarmSoundName) {
                    Section("알람") {
                        ForEach(AlarmSound.builtIn, id: \.self) { Text($0).tag($0) }
                    }
                    Section("macOS 기본 소리") {
                        ForEach(AlarmSound.system, id: \.self) { Text($0).tag($0) }
                    }
                    customSoundSection
                }
                Button {
                    AlarmSound.playPreview(settings.alarmSoundName, volume: settings.alarmVolume)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .buttonStyle(.borderless)
                .help("미리 듣기")
            }
            .onChange(of: settings.alarmSoundName) { _, name in
                AlarmSound.playPreview(name, volume: settings.alarmVolume)
            }

            customSoundButtons(selection: $settings.alarmSoundName, fallback: AlarmSound.defaultName)

            HStack {
                Image(systemName: "speaker.fill").font(.caption).foregroundColor(.secondary)
                Slider(value: $settings.alarmVolume, in: 0.1...1)
                Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundColor(.secondary)
            }
            Text("알람은 작게 시작해서 점점 커지고, 끄기 전까지 계속 울려요")
                .font(.caption2)
                .foregroundColor(.secondary)

            Button("알람 테스트 (지금 울리기)", action: onTestAlarm)
                .controlSize(.small)
        }
    }

    // MARK: - 내 소리 (shared by both sound pickers)

    @ViewBuilder
    private var customSoundSection: some View {
        if !customSounds.names.isEmpty {
            Section("내 소리") {
                ForEach(customSounds.names, id: \.self) { Text(CustomSounds.displayName($0)).tag($0) }
            }
        }
    }

    /// [내 소리 추가…] — and [삭제] while one of the user's files is selected.
    private func customSoundButtons(selection: Binding<String>, fallback: String) -> some View {
        HStack {
            Button("내 소리 추가…") {
                if let name = customSounds.pickAndImport() { selection.wrappedValue = name }
            }
            if CustomSounds.isCustom(selection.wrappedValue) {
                Button("‘\(CustomSounds.displayName(selection.wrappedValue))’ 삭제") {
                    customSounds.remove(selection.wrappedValue)
                    selection.wrappedValue = fallback
                }
                .help("내 소리 목록에서 지워요. 이 소리를 쓰던 다른 펫은 기본 소리로 울려요.")
            }
        }
        .controlSize(.small)
    }
}

// MARK: - Reminder draft

/// The "새 리마인더" form. ObservableObject instead of @State (no SwiftUI macro plugin in Command Line Tools).
private final class ReminderDraft: ObservableObject {
    /// Set while editing an existing reminder; nil = adding a new one.
    @Published var editingID: UUID?
    @Published var title = ""
    @Published var time = ReminderDraft.nextFiveMinutes()
    @Published var weekdays: Set<Int> = []

    var titleOrDefault: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "리마인더" : trimmed
    }

    func binding(for day: Int) -> Binding<Bool> {
        Binding(
            get: { self.weekdays.contains(day) },
            set: { on in if on { self.weekdays.insert(day) } else { self.weekdays.remove(day) } }
        )
    }

    func makeReminder() -> PetReminder {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0
        var reminder = weekdays.isEmpty
            ? PetReminder.once(title: titleOrDefault, hour: hour, minute: minute)
            : PetReminder(title: titleOrDefault, hour: hour, minute: minute, weekdays: weekdays.sorted())
        if let editingID { reminder.id = editingID }   // saving an edit turns it back on, without a snooze
        return reminder
    }

    /// Fill the form with an existing reminder to edit it.
    func load(_ reminder: PetReminder) {
        editingID = reminder.id
        title = reminder.title
        weekdays = Set(reminder.weekdays)
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        time = Calendar.current.date(from: DateComponents(year: today.year, month: today.month, day: today.day,
                                                          hour: reminder.hour, minute: reminder.minute)) ?? time
    }

    func reset() {
        editingID = nil
        title = ""
        weekdays = []
        time = Self.nextFiveMinutes()
    }

    private static func nextFiveMinutes() -> Date {
        let now = Date()
        let minute = Calendar.current.component(.minute, from: now)
        let rounded = Calendar.current.date(byAdding: .minute, value: 5 - minute % 5, to: now) ?? now
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: rounded)
        return Calendar.current.date(from: parts) ?? rounded
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Labeled Slider

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var displayMultiplier: Double = 1.0
    var step: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value * displayMultiplier))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
    }
}

// MARK: - Labeled Field

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Editable Slider (slider + number field + reset)

private struct EditableSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var displayMultiplier: Double = 1.0
    var resetValue: Double

    private var displayBinding: Binding<Double> {
        Binding(
            get: { (value * displayMultiplier).rounded() },
            set: { value = min(max($0 / displayMultiplier, range.lowerBound), range.upperBound) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                TextField("", value: displayBinding, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button {
                    value = resetValue
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("초기화")
            }
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Start at Login Toggle

// Backed by an ObservableObject instead of @State: the Command Line Tools
// toolchain ships without the SwiftUI macro plugin that @State needs.
private final class LoginItemModel: ObservableObject {
    @Published var isEnabled = SMAppService.mainApp.status == .enabled {
        didSet {
            guard oldValue != isEnabled else { return }
            try? isEnabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}

private struct StartAtLoginToggle: View {
    @StateObject private var model = LoginItemModel()

    var body: some View {
        Toggle("로그인 시 자동 실행", isOn: $model.isEnabled)
    }
}
