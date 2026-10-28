// PlaceholderAnimation.swift
// The built-in default pet: the alarm-clock cat from the app icon, gently bobbing and blinking.
// Shown on first launch (and for any pet without an imported file). No external files needed.

import CoreGraphics
import Foundation

enum PlaceholderAnimation {

    /// Generate the looping default-pet animation.
    /// - Parameters:
    ///   - pixels: frame width/height (the pet's natural size before scaling).
    ///   - frameCount: frames per loop at 24 fps (36 = 1.5 s).
    static func make(pixels: Int = 220, frameCount: Int = 36) -> FrameSequence {
        let content = AlarmCatArt.contentBounds
        let margin: CGFloat = 1.12                      // room for the bob and the sway
        let scale = CGFloat(pixels) / (max(content.width, content.height) * margin)
        let blinkFrames = Set([frameCount - 6, frameCount - 5])

        var frames: [CGImage] = []
        for i in 0..<frameCount {
            guard let ctx = CGContext(
                data: nil, width: pixels, height: pixels,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }

            let t = Double(i) / Double(frameCount)
            let bob = CGFloat(abs(sin(t * 2 * .pi))) * 14 * scale * 2   // little hops
            let sway = CGFloat(sin(t * 2 * .pi)) * 0.035                // slight side-to-side tilt

            ctx.translateBy(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2 + bob - 6 * scale * 2)
            ctx.rotate(by: sway)
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -content.midX, y: -content.midY)

            var options = AlarmCatArt.Options()
            options.background = false
            options.ringingArcs = false
            options.eyesClosed = blinkFrames.contains(i)
            AlarmCatArt.draw(in: ctx, options: options)

            if let image = ctx.makeImage() { frames.append(image) }
        }

        return FrameSequence(frames: frames, delays: Array(repeating: 1.0 / 24.0, count: frames.count))
    }
}
