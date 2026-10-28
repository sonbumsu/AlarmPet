// AppIconArt.swift
// The NotiPet mark: a cat-eared speech bubble with a smiling face and a blue notification dot
// on its right ear. Drawn with CoreGraphics so the app icon (scripts/make-icon.swift) and the
// menu bar glyph (MenuBarIcon) share one shape.
//
// Coordinates are in "design units": y grows downward, the bubble spans roughly x 313…808,
// y 303…820. `Mapping` turns them into the target context's space.

import CoreGraphics

enum AppIconArt {

    struct Mapping {
        /// Design units → context points.
        let scale: CGFloat
        /// Context point where design (0, 0) lands.
        let origin: CGPoint
        /// CoreGraphics contexts are y-up; the design is y-down.
        let flipY: Bool

        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: flipY ? origin.y - y * scale : origin.y + y * scale)
        }
        func len(_ v: CGFloat) -> CGFloat { v * scale }
    }

    private enum Colors {
        static let background = CGColor(srgbRed: 0.067, green: 0.067, blue: 0.063, alpha: 1)
        static let bubble = CGColor(srgbRed: 0.976, green: 0.984, blue: 0.965, alpha: 1)
        static let dot = CGColor(srgbRed: 0.290, green: 0.427, blue: 0.639, alpha: 1)
    }

    // MARK: - App icon

    /// Full-colour icon on a 1024×1024 y-up canvas (macOS icon grid: 824 pt rounded square).
    static func drawAppIcon(in ctx: CGContext) {
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
        ctx.addPath(tilePath)
        ctx.setFillColor(Colors.background)
        ctx.fillPath()
        ctx.restoreGState()

        // Design square 110…1010 (900 units) → tile 100…924 (824 pt).
        let scale = tile.width / 900
        let map = Mapping(scale: scale, origin: CGPoint(x: tile.minX - 110 * scale, y: tile.maxY + 110 * scale), flipY: true)
        drawMark(in: ctx, map: map, ink: Colors.bubble, cut: Colors.background, dot: Colors.dot, featureWidth: map.len(24))
    }

    // MARK: - Mark

    /// The bubble cat. `cut` paints the face and the ring around the dot; pass nil to punch
    /// them out (clear) instead, as the template menu bar glyph does.
    static func drawMark(in ctx: CGContext, map: Mapping, ink: CGColor, cut: CGColor?, dot: CGColor, featureWidth: CGFloat) {
        ctx.saveGState()
        ctx.setFillColor(ink)

        // Body.
        let body = CGRect(origin: map.p(313, map.flipY ? 747 : 392),
                          size: CGSize(width: map.len(495), height: map.len(355)))
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: map.len(105), cornerHeight: map.len(105), transform: nil))
        ctx.fillPath()

        // Ears and tail: triangles with rounded tips.
        fillRounded(ctx, [map.p(318, 470), map.p(392, 300), map.p(510, 420)], radius: map.len(36))
        fillRounded(ctx, [map.p(608, 420), map.p(728, 300), map.p(802, 470)], radius: map.len(36))
        fillRounded(ctx, [map.p(470, 735), map.p(470, 826), map.p(590, 735)], radius: map.len(18))

        // Face.
        if let cut { ctx.setStrokeColor(cut) } else { ctx.setBlendMode(.clear) }
        ctx.setLineWidth(featureWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for eyeX: CGFloat in [476, 645] {
            ctx.move(to: map.p(eyeX - 31, 576))
            ctx.addQuadCurve(to: map.p(eyeX + 31, 576), control: map.p(eyeX, 522))
        }
        ctx.move(to: map.p(514, 624))
        ctx.addQuadCurve(to: map.p(560, 622), control: map.p(537, 664))
        ctx.addQuadCurve(to: map.p(606, 624), control: map.p(583, 664))
        ctx.strokePath()

        // Notification dot with a ring cut into the ear.
        let center = map.p(765, 385)
        if let cut { ctx.setFillColor(cut) }
        ctx.fillEllipse(in: CGRect(x: center.x - map.len(68), y: center.y - map.len(68), width: map.len(136), height: map.len(136)))
        ctx.setBlendMode(.normal)
        ctx.setFillColor(dot)
        ctx.fillEllipse(in: CGRect(x: center.x - map.len(43), y: center.y - map.len(43), width: map.len(86), height: map.len(86)))
        ctx.restoreGState()
    }

    private static func fillRounded(_ ctx: CGContext, _ points: [CGPoint], radius: CGFloat) {
        let mid = CGPoint(x: (points[0].x + points[2].x) / 2, y: (points[0].y + points[2].y) / 2)
        ctx.move(to: mid)
        ctx.addArc(tangent1End: points[0], tangent2End: points[1], radius: radius)
        ctx.addArc(tangent1End: points[1], tangent2End: points[2], radius: radius)
        ctx.addArc(tangent1End: points[2], tangent2End: mid, radius: radius)
        ctx.closePath()
        ctx.fillPath()
    }
}
