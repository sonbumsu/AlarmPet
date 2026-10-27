// BubbleMedia.swift
// Downloads the GIF / image behind a MediaLink and plays it inside the bubble.

import AppKit
import ImageIO
import SwiftUI

/// A downloaded picture, ready to animate.
struct BubbleGIF {
    let data: Data
    let pixelSize: CGSize
    let firstFrame: CGImage
}

enum BubbleMediaState {
    case none           // the message has no media link
    case loading
    case loaded(BubbleGIF)
    case failed         // show the link as text, like before
}

enum BubbleMedia {

    private enum Constants {
        static let timeout: TimeInterval = 10
        static let maxBytes = 20 * 1024 * 1024
        static let cacheLimit = 12
    }

    // Main thread only.
    private static var cache: [URL: BubbleGIF] = [:]
    private static var cacheOrder: [URL] = []

    static func cached(_ link: URL) -> BubbleGIF? { cache[link] }

    /// Calls back on the main thread with the picture, or nil if it couldn't be loaded.
    static func load(_ link: URL, completion: @escaping (BubbleGIF?) -> Void) {
        if let hit = cache[link] { return completion(hit) }
        fetch(MediaLink.directURL(for: link), followPage: true) { gif in
            DispatchQueue.main.async {
                if let gif { remember(gif, for: link) }
                completion(gif)
            }
        }
    }

    private static func fetch(_ url: URL, followPage: Bool, completion: @escaping (BubbleGIF?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: Constants.timeout)
        request.setValue("Mozilla/5.0 (Macintosh) AlarmPet", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard let data, data.count <= Constants.maxBytes,
                  (response as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return completion(nil) }
            if let gif = decode(data) { return completion(gif) }
            // A web page (Tenor): follow its preview image once.
            if followPage, let html = String(data: data, encoding: .utf8),
               let image = MediaLink.previewImage(inHTML: html) {
                return fetch(image, followPage: false, completion: completion)
            }
            completion(nil)
        }.resume()
    }

    private static func decode(_ data: Data) -> BubbleGIF? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return BubbleGIF(data: data, pixelSize: CGSize(width: first.width, height: first.height), firstFrame: first)
    }

    private static func remember(_ gif: BubbleGIF, for link: URL) {
        if cache[link] == nil { cacheOrder.append(link) }
        cache[link] = gif
        while cacheOrder.count > Constants.cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }
}

// MARK: - View

/// Plays a GIF / APNG (or shows a still image) with ImageIO's own animator.
struct AnimatedImage: NSViewRepresentable {
    let gif: BubbleGIF

    func makeNSView(context: Context) -> AnimatedImageView {
        let view = AnimatedImageView()
        view.gif = gif
        return view
    }

    func updateNSView(_ view: AnimatedImageView, context: Context) {
        if view.gif?.data != gif.data { view.gif = gif }
    }
}

final class AnimatedImageView: NSView {

    var gif: BubbleGIF? {
        didSet { restart() }
    }

    /// Shared with the ImageIO callback so a replaced/removed view stops its animation.
    private final class Playback { var stopped = false }
    private var playback: Playback?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { playback?.stopped = true }

    /// Clicks go to the bubble (tap = dismiss).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    private func restart() {
        playback?.stopped = true
        playback = nil
        layer?.contents = gif?.firstFrame
        // Only animate while on screen (the bubble's size probe never gets a window).
        guard window != nil, let gif else { return }
        let current = Playback()
        playback = current
        CGAnimateImageDataWithBlock(gif.data as CFData, nil) { [weak self] _, image, stop in
            guard !current.stopped, let self else { stop.pointee = true; return }
            self.layer?.contents = image
        }
    }
}
