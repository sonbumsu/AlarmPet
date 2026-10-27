// PetMessage.swift
// One thing the pet should say. Every notification source produces these.

import Foundation

struct PetMessage: Equatable {
    var app: String       // "카카오톡"
    var body: String      // "집가고싶어ㅠㅠ"
    var sender: String?   // "손범수" (nil when the notification has no sender)
    var date: Date = Date()
    /// Only this pet (name or id) should say it. nil = every pet whose filters match.
    var target: String? = nil
    /// The app name before aliasing ("KakaoTalk" when `app` is "카톡") — used to find its icon.
    var sourceApp: String? = nil
}

extension PetMessage {
    /// "카카오톡: 집가고싶어ㅠㅠ - 손범수"
    var bubbleText: String {
        if let sender, !sender.isEmpty {
            return "\(app): \(body) - \(sender)"
        }
        return "\(app): \(body)"
    }

    /// GIF / image links in the body (shown as a picture in the bubble).
    var mediaLinks: [URL] { MediaLink.find(in: body) }

    /// What TTS reads out loud. GIF links are read as "움짤", not letter by letter.
    var spokenText: String {
        var said = body
        if !mediaLinks.isEmpty {
            said = MediaLink.removing(from: body)
            if said.isEmpty { said = "움짤" }
        }
        if let sender, !sender.isEmpty {
            return "\(app), \(sender). \(said)"
        }
        return "\(app). \(said)"
    }
}
