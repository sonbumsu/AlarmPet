// NotificationTests.swift
// Which pet says which app, bubble text, saved data compatibility, local HTTP.

import Foundation

func notificationTests() {
    Check.section("저장된 펫 데이터 호환")
    let old = legacyRecord(extra: ["soundName": "삐롱"])
    Check.that(old.label == "kurukuru" && old.scale == 1.2, "old record (with removed flip keys) still loads")
    Check.that(old.speaksNotifications && old.allowedApps.isEmpty && old.soundName == "삐롱", "speech fields get defaults, keep saved ones")
    let roundTrip = try! PropertyListDecoder().decode(PetRecord.self, from: PropertyListEncoder().encode(old))
    Check.that(roundTrip == old, "record round-trips")

    Check.section("펫별 앱 필터")
    let suite = "alarmpet-tests"
    UserDefaults().removePersistentDomain(forName: suite)
    let notifications = NotificationSettings(defaults: UserDefaults(suiteName: suite)!)
    notifications.appAliases = "KakaoTalk=카톡"
    defer { UserDefaults().removePersistentDomain(forName: suite) }

    func pet(_ allowed: String, _ blocked: String = "", speaks: Bool = true, label: String = "p") -> AppSettings {
        var record = PetRecord.default(instanceID: "pet-\(label)", index: 1)
        record.label = label
        record.allowedApps = allowed
        record.blockedApps = blocked
        record.speaksNotifications = speaks
        return AppSettings(record: record)
    }

    let kakao = notifications.displayName(for: "KakaoTalk")
    Check.that(kakao == "카톡", "alias KakaoTalk → 카톡")
    Check.that(pet("카톡").speaks(app: "KakaoTalk", displayName: kakao), "matches the alias")
    Check.that(pet("kakaotalk").speaks(app: "KakaoTalk", displayName: kakao), "matches original name, any case")
    Check.that(!pet("Discord").speaks(app: "KakaoTalk", displayName: kakao), "Discord pet ignores KakaoTalk")
    Check.that(pet("Discord").speaks(app: "Discord", displayName: "Discord"), "Discord pet says Discord")
    Check.that(pet("").speaks(app: "Slack", displayName: "Slack"), "empty filter = every app")
    Check.that(!pet("", "Slack, 메일").speaks(app: "Slack", displayName: "Slack"), "blocked list wins")
    Check.that(!pet("", speaks: false).speaks(app: "Slack", displayName: "Slack"), "speaks off = silent")
    let named = pet("", label: "디코펫")
    Check.that(named.matches(target: "디코펫") && named.matches(target: "pet-디코펫") && !named.matches(target: "다른펫"), "target by name / id")

    if FileManager.default.fileExists(atPath: "/Applications/KakaoTalk.app") {
        Check.that(pet("카카오톡").speaks(app: "KakaoTalk", displayName: "KakaoTalk"), "카카오톡 ↔ KakaoTalk (installed app names)")
        Check.that(AppDirectory.url(for: "카카오톡")?.lastPathComponent == "KakaoTalk.app", "icon lookup by Korean name")
    }
    Check.that(pet("스크립트 편집기").speaks(app: "Script Editor", displayName: "Script Editor"), "스크립트 편집기 ↔ Script Editor")

    Check.section("말풍선 문구")
    let message = PetMessage(app: "카카오톡", body: "집가고싶어ㅠㅠ", sender: "손범수")
    Check.that(message.bubbleText == "카카오톡: 집가고싶어ㅠㅠ - 손범수", "bubbleText with sender")
    Check.that(PetMessage(app: "리마인더", body: "물", sender: nil).bubbleText == "리마인더: 물", "bubbleText without sender")
    Check.that(message.spokenText == "카카오톡, 손범수. 집가고싶어ㅠㅠ", "spokenText")

    Check.section("로컬 HTTP")
    let json = LocalServerSource.message(from: Data(#"{"app":"터미널","body":"빌드 끝","sender":"CI","pet":"kurukuru"}"#.utf8))
    Check.that(json?.app == "터미널" && json?.body == "빌드 끝" && json?.sender == "CI" && json?.target == "kurukuru", "JSON body")
    let alt = LocalServerSource.message(from: Data(#"{"text":"hi","title":"A"}"#.utf8))
    Check.that(alt?.body == "hi" && alt?.sender == "A" && alt?.app == "알림펫", "text/title aliases, default app")
    Check.that(LocalServerSource.message(from: Data("그냥 글자".utf8))?.body == "그냥 글자", "plain text body")
    Check.that(LocalServerSource.message(from: Data()) == nil && LocalServerSource.message(from: Data(#"{"app":"x"}"#.utf8)) == nil,
               "empty body rejected")

    // Port already taken by someone else → a readable message instead of silence.
    let blocker = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    address.sin_port = 0   // any free port
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(blocker, 1)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(blocker, $0, &length) } }
    let takenPort = UInt16(bigEndian: address.sin_port)

    let server = LocalServerSource(port: takenPort)
    var status: String?
    var reported = false
    server.onStatusChange = { status = $0; reported = true }
    server.start()
    Check.wait(seconds: 3) { reported }
    Check.that(status?.contains("다른 프로그램이 쓰고 있어요") == true, "port in use → \(status ?? "no message")")
    server.stop()
    close(blocker)

    Check.section("소리 / 기본 펫")
    for name in AlarmSound.builtIn {
        let duration = AlarmSound.makeSound(name)?.duration ?? 0
        Check.that(duration > 0.9 && duration < 1.5, "alarm sound \(name) (\(String(format: "%.2f", duration))s)")
    }
    let pet = PlaceholderAnimation.make()
    Check.that(pet.count == 36 && pet.frames.allSatisfy { $0.width == 220 && $0.height == 220 }, "default pet: 36 frames, 220px")
}
