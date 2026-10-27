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

    Check.section("움짤 링크")
    let tenor = "https://tenor.com/view/cat-cat-dance-gif-7523542997650649169"
    let gifMessage = PetMessage(app: "Discord", body: "이거 봐 \(tenor)", sender: "A")
    Check.that(gifMessage.mediaLinks.map(\.absoluteString) == [tenor], "finds a Tenor link")
    Check.that(MediaLink.removing(from: gifMessage.body) == "이거 봐", "removes the link from the text")
    Check.that(MediaLink.removing(from: "<\(tenor)>") == "", "only a link (Discord <...>) → empty")
    Check.that(gifMessage.spokenText == "Discord, A. 이거 봐", "TTS skips the link")
    Check.that(PetMessage(app: "D", body: tenor, sender: nil).spokenText == "D. 움짤", "TTS says 움짤 for a lone GIF")
    Check.that(MediaLink.find(in: "https://cdn.discordapp.com/attachments/1/2/cat.GIF?ex=abc").count == 1, "direct .gif with query")
    Check.that(MediaLink.find(in: "https://github.com/sonbumsu/AlarmPet 그리고 https://tenor.com/search/cat").isEmpty, "ordinary links stay links")
    Check.that(MediaLink.directURL(for: URL(string: "https://giphy.com/gifs/ai-cat-meme-774uK11mxE3W0cjE8L")!).absoluteString
               == "https://media.giphy.com/media/774uK11mxE3W0cjE8L/200.gif", "Giphy page → direct gif")
    let klipy = URL(string: "https://klipy.com/gifs/-33785")!
    Check.that(MediaLink.find(in: "<\(klipy.absoluteString)>") == [klipy], "finds a Klipy link")
    Check.that(MediaLink.find(in: "https://klipy.com/gifs").isEmpty, "Klipy list page stays a link")
    Check.that(MediaLink.klipyAPIURL(for: klipy, key: " KEY\n")?.absoluteString
               == "https://api.klipy.com/api/v1/KEY/gifs/-33785", "Klipy link → API URL")
    Check.that(MediaLink.klipyAPIURL(for: klipy, key: "") == nil, "no Klipy key → no API call")
    let klipyJSON = #"{"result":true,"data":{"slug":"-33785","file":{"hd":{"gif":{"url":"https://static.klipy.com/hd.gif"}},"md":{"gif":{"url":"https://static.klipy.com/md.gif"}}}}}"#
    Check.that(MediaLink.klipyGIF(inJSON: Data(klipyJSON.utf8))?.absoluteString == "https://static.klipy.com/md.gif", "Klipy reply → md gif")
    Check.that(MediaLink.klipyGIF(inJSON: Data(#"{"result":false,"data":[]}"#.utf8)) == nil, "Klipy not found → nil")
    let html = #"<meta class="dynamic" name="twitter:image" content="https://x/t.gif"><meta class="dynamic" property="og:image" content="https://media1.tenor.com/m/a/cat.gif?a=1&amp;b=2">"#
    Check.that(MediaLink.previewImage(inHTML: html)?.absoluteString == "https://media1.tenor.com/m/a/cat.gif?a=1&b=2", "og:image wins, any attribute order")

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

    Check.section("내 소리")
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("alarmpet-sounds-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: temp) }
    let library = CustomSounds(directory: temp.appendingPathComponent("Sounds"))
    let source = temp.appendingPathComponent("카톡왔숑.wav")
    try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    try! PetSound.wav(duration: 0.5, frequency: { _ in 440 }, envelope: { _ in 1 }).write(to: source)

    let first = try! library.importFile(source)
    let second = try! library.importFile(source)
    Check.that(first == "내소리:카톡왔숑.wav" && second == "내소리:카톡왔숑 2.wav", "import copies, same name gets a number")
    Check.that(library.names == [first, second], "library lists imported sounds")
    Check.that(CustomSounds.displayName(first) == "카톡왔숑" && CustomSounds.displayName("뿅") == "뿅", "display name drops prefix and extension")
    Check.that(abs((library.makeSound(first)?.duration ?? 0) - 0.5) < 0.01, "imported file plays")
    try! FileManager.default.removeItem(at: source)
    Check.that(library.makeSound(first) != nil, "still plays after the original is deleted")
    library.remove(first)
    Check.that(library.names == [second] && library.makeSound(first) == nil, "remove")
    Check.that(library.url(for: "내소리:../../etc/passwd") == nil, "no paths outside the folder")
    Check.that(AlarmSound.makeSound("내소리:없는파일.mp3") != nil, "missing alarm file → default alarm still rings")
}
