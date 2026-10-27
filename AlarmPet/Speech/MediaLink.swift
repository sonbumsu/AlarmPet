// MediaLink.swift
// Finds GIF / image links in a notification body (Tenor, Giphy, or a direct .gif/.png/... file)
// so the bubble can show the picture instead of the raw link.

import Foundation

enum MediaLink {

    static let imageExtensions: Set<String> = ["gif", "png", "jpg", "jpeg", "webp", "apng", "heic"]

    /// Media links in `text`, in order.
    static func find(in text: String) -> [URL] {
        matches(in: text).map(\.url)
    }

    /// `text` with the media links taken out ("" when it was only a GIF link).
    static func removing(from text: String) -> String {
        var result = text
        for match in matches(in: text).reversed() {
            result.removeSubrange(match.range)
        }
        // Discord wraps links as <https://...>; drop the leftover brackets, then tidy whitespace.
        result = result.replacingOccurrences(of: "<>", with: "")
        return result
            .components(separatedBy: .newlines)
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func isMedia(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return false }
        if imageExtensions.contains(url.pathExtension.lowercased()) { return true }
        if (host == "tenor.com" || host.hasSuffix(".tenor.com")) && url.path.hasPrefix("/view/") { return true }
        if (host == "giphy.com" || host == "www.giphy.com") && url.path.hasPrefix("/gifs/") { return true }
        return false
    }

    /// Where the picture itself can be downloaded from without opening the page first.
    /// giphy.com/gifs/cat-dance-ABC123 → media.giphy.com/media/ABC123/200.gif
    /// (its page only advertises a .webp; 200.gif is the 200px-tall copy — a fraction of the original's size).
    static func directURL(for url: URL) -> URL {
        let host = url.host?.lowercased() ?? ""
        if (host == "giphy.com" || host == "www.giphy.com") && url.path.hasPrefix("/gifs/"),
           let id = url.lastPathComponent.split(separator: "-").last, !id.isEmpty {
            return URL(string: "https://media.giphy.com/media/\(id)/200.gif") ?? url
        }
        return url
    }

    /// The preview image a web page advertises (`og:image`, else `twitter:image`) — Tenor's is the GIF.
    static func previewImage(inHTML html: String) -> URL? {
        let tags = html.ranges(of: #"<meta\b[^>]*>"#)
        var twitter: URL?
        for range in tags {
            let tag = String(html[range])
            guard let key = tag.firstCapture(of: #"(?:property|name)\s*=\s*["']([^"']+)["']"#),
                  key == "og:image" || key == "twitter:image",
                  let content = tag.firstCapture(of: #"content\s*=\s*["']([^"']+)["']"#),
                  let url = URL(string: content.replacingOccurrences(of: "&amp;", with: "&")) else { continue }
            if key == "og:image" { return url }
            twitter = twitter ?? url
        }
        return twitter
    }

    // MARK: - Private

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func matches(in text: String) -> [(range: Range<String.Index>, url: URL)] {
        guard let detector else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let url = match.url, isMedia(url), let range = Range(match.range, in: text) else { return nil }
            return (range, url)
        }
    }
}

private extension String {
    func ranges(of pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: self, range: NSRange(startIndex..., in: self)).compactMap { Range($0.range, in: self) }
    }

    func firstCapture(of pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              let range = Range(match.range(at: 1), in: self) else { return nil }
        return String(self[range])
    }
}
