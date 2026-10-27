// NotificationSettingsView.swift
// App-wide notification settings panel (master switch, aliases, sources).
// Bubble size, sound, and app filters live in each pet's own settings ("알림" tab).

import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var settings: NotificationSettings
    var onTestBubble: () -> Void
    var onRequestAccessibility: () -> Void

    @StateObject private var permission = PermissionModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // ── Global ───────────────────────────────────────────────────
            Header("전체")

            Toggle("알림 말풍선 켜기 (모든 펫)", isOn: $settings.bubbleEnabled)

            Text("말풍선 크기·소리·말할 앱은 펫마다 따로 정해요 → 펫 우클릭 → 설정… → 알림 탭")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("말풍선 테스트 (보이는 펫 모두)", action: onTestBubble)
                .controlSize(.small)

            Divider()

            // ── App names ────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 2) {
                Text("앱 이름 바꾸기 (한 줄에 하나: 원래이름=표시이름)")
                    .font(.caption).foregroundColor(.secondary)
                TextEditor(text: $settings.appAliases)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }

            Divider()

            // ── Sources ──────────────────────────────────────────────────
            Header("알림 가져오기")

            Toggle("시스템 알림 읽기 (카카오톡 등)", isOn: $settings.systemNotificationsEnabled)
            if settings.systemNotificationsEnabled && !permission.isTrusted {
                HStack {
                    Text("손쉬운 사용 권한이 필요해요")
                        .font(.caption).foregroundColor(.orange)
                    Spacer()
                    Button("권한 열기") {
                        onRequestAccessibility()
                    }
                    .controlSize(.small)
                }
            }

            if settings.systemNotificationsEnabled {
                Toggle("원래 알림 배너 숨기기", isOn: $settings.hideOriginalBanners)
                    .padding(.leading, 16)
                Text("펫이 말풍선으로 말할 알림만 닫아요. 알림 센터 기록에는 남아요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
            }

            Toggle("로컬 HTTP로 말 시키기", isOn: $settings.localServerEnabled)
            if settings.localServerEnabled {
                HStack(spacing: 6) {
                    Text("포트").font(.caption).foregroundColor(.secondary)
                    TextField("7777", value: portBinding, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("(1024~65535, 엔터로 적용)").font(.caption2).foregroundColor(.secondary)
                }
                if let error = settings.localServerError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("curl -X POST localhost:\(String(settings.localServerPort))/say -d '{\"app\":\"터미널\",\"body\":\"빌드 끝!\",\"pet\":\"펫 1\"}'")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\"pet\"을 빼면 조건에 맞는 모든 펫이 말해요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            permission.isTrusted = AccessibilitySource.isTrusted
        }
    }

    /// Ports below 1024 need root; clamp to the usable range.
    private var portBinding: Binding<Int> {
        Binding(
            get: { settings.localServerPort },
            set: { settings.localServerPort = min(max($0, 1024), 65535) }
        )
    }
}

/// ObservableObject instead of @State (no SwiftUI macro plugin in Command Line Tools).
private final class PermissionModel: ObservableObject {
    @Published var isTrusted = AccessibilitySource.isTrusted
}

private struct Header: View {
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
