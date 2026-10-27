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

    /// What TTS reads out loud.
    var spokenText: String {
        if let sender, !sender.isEmpty {
            return "\(app), \(sender). \(body)"
        }
        return "\(app). \(body)"
    }
}
