// MenuBarIcon.swift
// Menu bar glyph matching the app icon: the bubble cat with its notification dot, drawn as a
// template image (face and dot ring punched out) so macOS tints it for light/dark menu bars.

import AppKit

enum MenuBarIcon {

    private enum Metrics {
        static let size: CGFloat = 18
        /// Design units the glyph spans (AppIconArt): x 300…830, y 290…830.
        static let designLeft: CGFloat = 300
        static let designTop: CGFloat = 290
        static let designWidth: CGFloat = 530
        static let inset: CGFloat = 0.5
        /// Thicker than the icon's proportions so the face survives at 18 pt.
        static let featureWidth: CGFloat = 1.4
    }

    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: Metrics.size, height: Metrics.size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let scale = (Metrics.size - Metrics.inset * 2) / Metrics.designWidth
            let map = AppIconArt.Mapping(
                scale: scale,
                origin: CGPoint(x: Metrics.inset - Metrics.designLeft * scale,
                                y: Metrics.size - Metrics.inset + Metrics.designTop * scale),
                flipY: true)
            let black = NSColor.black.cgColor
            AppIconArt.drawMark(in: ctx, map: map, ink: black, cut: nil, dot: black, featureWidth: Metrics.featureWidth)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "알림펫"
        return image
    }
}
