// MenuBarIcon.swift
// Menu bar glyph matching the app icon: a cat-eared alarm clock, drawn as a template image
// so macOS tints it for light/dark menu bars.

import AppKit

enum MenuBarIcon {

    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.set()

            // Ears (the alarm bells).
            for side in [-1.0, 1.0] {
                let s = CGFloat(side)
                let ear = NSBezierPath()
                ear.move(to: NSPoint(x: 9 + s * 2.2, y: 13.2))
                ear.line(to: NSPoint(x: 9 + s * 6.3, y: 16.6))
                ear.line(to: NSPoint(x: 9 + s * 6.4, y: 10.6))
                ear.close()
                ear.lineJoinStyle = .round
                ear.fill()
            }

            // Clock body.
            let body = NSBezierPath(ovalIn: NSRect(x: 3.2, y: 2.6, width: 11.6, height: 11.6))
            body.lineWidth = 1.6
            body.stroke()

            // Legs.
            let legs = NSBezierPath()
            legs.move(to: NSPoint(x: 5.4, y: 3.6)); legs.line(to: NSPoint(x: 4.2, y: 1.2))
            legs.move(to: NSPoint(x: 12.6, y: 3.6)); legs.line(to: NSPoint(x: 13.8, y: 1.2))
            legs.lineWidth = 1.6
            legs.lineCapStyle = .round
            legs.stroke()

            // Striker nub between the ears.
            NSBezierPath(ovalIn: NSRect(x: 7.6, y: 14.6, width: 2.8, height: 2.0)).fill()

            // Eyes, set wide and high so they read as eyes (a mouth is just noise at 18 pt).
            NSBezierPath(ovalIn: NSRect(x: 5.7, y: 8.4, width: 1.8, height: 2.1)).fill()
            NSBezierPath(ovalIn: NSRect(x: 10.5, y: 8.4, width: 1.8, height: 2.1)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "알림펫"
        return image
    }
}
