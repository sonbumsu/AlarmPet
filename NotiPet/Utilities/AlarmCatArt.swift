// AlarmCatArt.swift
// The alarm-clock cat: an alarm clock whose bells are cat ears and whose dial is a cat face.
// Used for the app icon (scripts/make-icon.swift) and the built-in default pet (PlaceholderAnimation).
// Drawn on a 1024×1024 canvas, y up; callers scale/translate the context.

import CoreGraphics

enum AlarmCatArt {

    struct Options {
        /// Rounded-square app-icon tile behind the cat.
        var background = true
        /// "Ringing" arcs beside the ears.
        var ringingArcs = true
        /// Happy closed eyes (blink frame).
        var eyesClosed = false
    }

    /// Roughly where the cat (ears to legs) sits on the canvas, for cropping.
    static let contentBounds = CGRect(x: 240, y: 160, width: 544, height: 700)

    // MARK: - Palette

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    private static let bgTop     = rgb(0xFFD66B)
    private static let bgBottom  = rgb(0xFF9B54)
    private static let body      = rgb(0xFF6F61)   // clock ring, ears, striker
    private static let bodyDark  = rgb(0xE5584C)   // legs, striker stem
    private static let earInner  = rgb(0xFFB4AE)
    private static let face      = rgb(0xFFF9F0)
    private static let ink       = rgb(0x3A2E39)
    private static let blush     = rgb(0xFF8FA3, 0.45)
    private static let nosePink  = rgb(0xFF7B93)
    private static let whisker   = rgb(0x3A2E39, 0.55)
    private static let ringLines = rgb(0xFFFFFF, 0.95)

    // MARK: - Geometry

    private static let center = CGPoint(x: 512, y: 470)
    private static let ringRadius: CGFloat = 268
    private static let ringWidth: CGFloat = 36

    private static func roundedTriangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (a.x + c.x) / 2, y: (a.y + c.y) / 2))
        path.addArc(tangent1End: a, tangent2End: b, radius: radius)
        path.addArc(tangent1End: b, tangent2End: c, radius: radius)
        path.addArc(tangent1End: c, tangent2End: a, radius: radius)
        path.closeSubpath()
        return path
    }

    // MARK: - Drawing

    static func draw(in ctx: CGContext, options: Options = Options()) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if options.background {
            // macOS-style rounded square with a warm gradient.
            let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                              cornerWidth: 185, cornerHeight: 185, transform: nil)
            ctx.addPath(tile)
            ctx.clip()
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                      colors: [bgTop, bgBottom] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
        }

        if options.ringingArcs {
            ctx.setStrokeColor(ringLines)
            ctx.setLineCap(.round)
            for side in [-1.0, 1.0] {
                for (i, r) in [CGFloat(70), 118].enumerated() {
                    ctx.setLineWidth(i == 0 ? 22 : 18)
                    let c = CGPoint(x: 512 + side * 255, y: 735)
                    let mid = side < 0 ? CGFloat.pi * 0.83 : CGFloat.pi * 0.17
                    ctx.addArc(center: c, radius: r, startAngle: mid - 0.42, endAngle: mid + 0.42, clockwise: false)
                    ctx.strokePath()
                }
            }
        }

        // Soft drop shadow for the whole body.
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: rgb(0x8A3A10, 0.35))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        drawBody(ctx)
        ctx.endTransparencyLayer()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        drawFace(ctx, eyesClosed: options.eyesClosed)
    }

    private static func drawBody(_ ctx: CGContext) {
        // Legs.
        ctx.setFillColor(bodyDark)
        for side in [-1.0, 1.0] {
            ctx.saveGState()
            ctx.translateBy(x: 512 + side * 150, y: 225)
            ctx.rotate(by: side * 0.55)
            ctx.addPath(CGPath(roundedRect: CGRect(x: -26, y: -55, width: 52, height: 110), cornerWidth: 26, cornerHeight: 26, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Striker (the little hammer between the ears).
        ctx.setFillColor(bodyDark)
        ctx.fill(CGRect(x: 499, y: 720, width: 26, height: 60))
        ctx.setFillColor(body)
        ctx.fillEllipse(in: CGRect(x: 512 - 38, y: 765, width: 76, height: 48))

        // Cat ears (where an alarm clock would have its bells).
        for side in [-1.0, 1.0] {
            let s = CGFloat(side)
            ctx.addPath(roundedTriangle(CGPoint(x: 512 + s * 95, y: 700),
                                        CGPoint(x: 512 + s * 250, y: 850),
                                        CGPoint(x: 512 + s * 265, y: 600), radius: 38))
            ctx.setFillColor(body)
            ctx.fillPath()
            ctx.addPath(roundedTriangle(CGPoint(x: 512 + s * 140, y: 690),
                                        CGPoint(x: 512 + s * 238, y: 790),
                                        CGPoint(x: 512 + s * 240, y: 640), radius: 26))
            ctx.setFillColor(earInner)
            ctx.fillPath()
        }

        // Clock ring + face.
        ctx.setFillColor(body)
        ctx.fillEllipse(in: CGRect(x: center.x - ringRadius, y: center.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
        let faceRadius = ringRadius - ringWidth
        ctx.setFillColor(face)
        ctx.fillEllipse(in: CGRect(x: center.x - faceRadius, y: center.y - faceRadius, width: faceRadius * 2, height: faceRadius * 2))
    }

    private static func drawFace(_ ctx: CGContext, eyesClosed: Bool) {
        let faceRadius = ringRadius - ringWidth

        // Clock ticks at 12 and 6.
        ctx.setFillColor(rgb(0x3A2E39, 0.35))
        for y in [center.y + faceRadius - 52, center.y - faceRadius + 18] {
            ctx.addPath(CGPath(roundedRect: CGRect(x: 512 - 9, y: y, width: 18, height: 34), cornerWidth: 9, cornerHeight: 9, transform: nil))
            ctx.fillPath()
        }

        // Cheeks.
        ctx.setFillColor(blush)
        for x in [CGFloat(372), 652] {
            ctx.fillEllipse(in: CGRect(x: x - 48, y: 392, width: 96, height: 56))
        }

        // Eyes.
        for x in [CGFloat(428), 596] {
            if eyesClosed {
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(12)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: x - 32, y: 522))
                ctx.addQuadCurve(to: CGPoint(x: x + 32, y: 522), control: CGPoint(x: x, y: 494))
                ctx.strokePath()
            } else {
                ctx.setFillColor(ink)
                ctx.fillEllipse(in: CGRect(x: x - 36, y: 478, width: 72, height: 80))
                ctx.setFillColor(rgb(0xFFFFFF))
                ctx.fillEllipse(in: CGRect(x: x - 4, y: 524, width: 24, height: 24))
                ctx.fillEllipse(in: CGRect(x: x - 22, y: 498, width: 10, height: 10))
            }
        }

        // Nose.
        ctx.addPath(roundedTriangle(CGPoint(x: 490, y: 452), CGPoint(x: 534, y: 452), CGPoint(x: 512, y: 424), radius: 8))
        ctx.setFillColor(nosePink)
        ctx.fillPath()

        // ω mouth.
        ctx.setStrokeColor(ink)
        ctx.setLineWidth(11)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: 512, y: 426))
        ctx.addQuadCurve(to: CGPoint(x: 470, y: 398), control: CGPoint(x: 505, y: 388))
        ctx.move(to: CGPoint(x: 512, y: 426))
        ctx.addQuadCurve(to: CGPoint(x: 554, y: 398), control: CGPoint(x: 519, y: 388))
        ctx.strokePath()

        // Whiskers.
        ctx.setStrokeColor(whisker)
        ctx.setLineWidth(8)
        for side in [-1.0, 1.0] {
            let s = CGFloat(side)
            for (dy, tilt) in [(CGFloat(18), CGFloat(18)), (-12, -10)] {
                ctx.move(to: CGPoint(x: 512 + s * 150, y: 430 + dy))
                ctx.addLine(to: CGPoint(x: 512 + s * 250, y: 430 + dy + tilt))
            }
        }
        ctx.strokePath()
    }
}
