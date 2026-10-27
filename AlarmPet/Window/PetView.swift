// PetView.swift
// NSView hosting the CALayer render target.
// Handles frame display, drag-to-reposition, file drop, rotation,
// and the ⌥ edit mode (corner handles = resize, top knob = rotate).
//
// Layer tree:
//   view.layer
//   └── contentLayer      ← rotated, sized to (natural size × scale), centered in the view
//       ├── imageLayer    ← shows the current CGImage
//       ├── videoLayer    ← optional AVPlayerLayer
//       ├── outlineLayer  ← edit mode: bounding rect + line to rotate knob
//       └── knobLayer     ← edit mode: 4 corner squares + rotate circle
//
// The window is always the rotated bounding box plus `Metrics.padding` on each side,
// so the content center is always the window center.

import AppKit
import QuartzCore
import CoreGraphics

protocol PetViewDelegate: AnyObject {
    func petView(_ view: PetView, didDropFileAt url: URL)
    func petViewDidFinishDrag(_ view: PetView)
    /// `center` is the new pet center in screen coordinates; nil keeps the current center.
    func petView(_ view: PetView, requestScale scale: Double, center: NSPoint?)
    func petView(_ view: PetView, requestRotation degrees: Double)
    func petViewMouseMoved(_ view: PetView)
    func petViewContextMenu(_ view: PetView) -> NSMenu?
}

final class PetView: NSView {

    enum Metrics {
        /// Transparent margin around the pet. Must fit the rotate knob.
        static let padding: CGFloat = 40
        static let knobRadius: CGFloat = 6
        static let rotateKnobOffset: CGFloat = 26
        static let knobHitSlop: CGFloat = 12
        static let opaqueAlphaThreshold: UInt8 = 20
    }

    // MARK: - Public
    weak var delegate: PetViewDelegate?
    var lockPosition: Bool  = false
    var clickThrough: Bool  = false

    /// Clockwise degrees.
    var rotationDegrees: Double = 0 { didSet { applyRotation() } }

    /// Current scale and its allowed range, used by scroll / pinch / handle math.
    var scale: Double = 1.0
    var scaleRange: ClosedRange<Double> = 0.1...8.0

    /// Unrotated pet size in points (natural size × scale).
    var contentSize: CGSize = CGSize(width: 200, height: 200) { didSet { layoutContent() } }

    /// ⌥ edit mode: shows resize / rotate handles.
    var isEditing: Bool = false {
        didSet {
            guard oldValue != isEditing else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            outlineLayer.isHidden = !isEditing
            knobLayer.isHidden = !isEditing
            CATransaction.commit()
        }
    }

    // MARK: - Layers
    private let contentLayer = CALayer()
    private let imageLayer   = CALayer()
    private let outlineLayer = CAShapeLayer()
    private let knobLayer    = CAShapeLayer()
    private var videoLayer: CALayer?
    private var currentFrame: CGImage?

    // MARK: - Drag State
    private enum Drag {
        case move(startMouse: NSPoint, startOrigin: NSPoint)
        case scale(fixed: NSPoint, corner: NSPoint, startScale: Double)
        case rotate(center: NSPoint)
    }
    private var drag: Drag?

    private enum Handle {
        case corner(CGPoint)   // local point in contentLayer
        case rotate
    }

    // MARK: - Init

    override init(frame: NSRect) { super.init(frame: frame); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear

        contentLayer.backgroundColor = CGColor.clear
        layer?.addSublayer(contentLayer)

        imageLayer.contentsGravity = .resizeAspect
        imageLayer.backgroundColor = CGColor.clear
        contentLayer.addSublayer(imageLayer)

        let accent = NSColor.controlAccentColor.cgColor
        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = accent
        outlineLayer.lineWidth = 1.5
        outlineLayer.lineDashPattern = [5, 3]
        outlineLayer.isHidden = true
        contentLayer.addSublayer(outlineLayer)

        knobLayer.fillColor = CGColor.white
        knobLayer.strokeColor = accent
        knobLayer.lineWidth = 1.5
        knobLayer.isHidden = true
        contentLayer.addSublayer(knobLayer)

        layoutContent()
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - Frame Display

    func display(frame: CGImage) {
        currentFrame = frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = frame
        CATransaction.commit()
    }

    /// Attach (or detach with nil) a video layer that should rotate with the pet.
    func setVideoLayer(_ newLayer: CALayer?) {
        videoLayer?.removeFromSuperlayer()
        videoLayer = newLayer
        if let newLayer {
            contentLayer.insertSublayer(newLayer, above: imageLayer)
            imageLayer.contents = nil
            currentFrame = nil
        }
        layoutContent()
    }

    // MARK: - Transforms

    private func applyRotation() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Layer space is y-up, so a positive CA angle is counter-clockwise.
        contentLayer.transform = CATransform3DMakeRotation(-rotationDegrees * .pi / 180, 0, 0, 1)
        CATransaction.commit()
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutContent()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    private func layoutContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let local = CGRect(origin: .zero, size: contentSize)
        contentLayer.bounds = local
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        imageLayer.bounds = local
        imageLayer.position = CGPoint(x: local.midX, y: local.midY)
        videoLayer?.frame = local
        outlineLayer.frame = local
        knobLayer.frame = local
        updateHandlePaths()

        CATransaction.commit()
    }

    private func updateHandlePaths() {
        let w = contentSize.width, h = contentSize.height
        let r = Metrics.knobRadius
        let knobCenter = CGPoint(x: w / 2, y: h + Metrics.rotateKnobOffset)

        let outline = CGMutablePath()
        outline.addRect(CGRect(x: 0, y: 0, width: w, height: h))
        outline.move(to: CGPoint(x: w / 2, y: h))
        outline.addLine(to: CGPoint(x: knobCenter.x, y: knobCenter.y - r))
        outlineLayer.path = outline

        let knobs = CGMutablePath()
        for corner in cornerPoints() {
            knobs.addRect(CGRect(x: corner.x - r, y: corner.y - r, width: r * 2, height: r * 2))
        }
        knobs.addEllipse(in: CGRect(x: knobCenter.x - r, y: knobCenter.y - r, width: r * 2, height: r * 2))
        knobLayer.path = knobs
    }

    private func cornerPoints() -> [CGPoint] {
        let w = contentSize.width, h = contentSize.height
        return [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0), CGPoint(x: 0, y: h), CGPoint(x: w, y: h)]
    }

    // MARK: - Talking animation

    func setTalking(_ talking: Bool) {
        if talking {
            guard contentLayer.animation(forKey: "talk") == nil else { return }
            let bounce = CAKeyframeAnimation(keyPath: "position.y")
            bounce.values = [0, 10, 0, 5, 0]
            bounce.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            bounce.isAdditive = true
            bounce.duration = 0.7
            bounce.repeatCount = .infinity
            contentLayer.add(bounce, forKey: "talk")
        } else {
            contentLayer.removeAnimation(forKey: "talk")
        }
    }

    /// Alarm: shake side to side and hop, like an alarm clock rattling.
    func setRinging(_ ringing: Bool) {
        if ringing {
            guard contentLayer.animation(forKey: "ring") == nil else { return }
            let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            shake.values = [0, 0.14, -0.14, 0.12, -0.12, 0.08, -0.08, 0]
            shake.isAdditive = true
            shake.duration = 0.6

            let hop = CAKeyframeAnimation(keyPath: "position.y")
            hop.values = [0, 12, 0, 6, 0]
            hop.isAdditive = true
            hop.duration = 0.6

            let group = CAAnimationGroup()
            group.animations = [shake, hop]
            group.duration = 1.0          // 0.6 s of rattling, then a short rest
            group.repeatCount = .infinity
            contentLayer.add(group, forKey: "ring")
        } else {
            contentLayer.removeAnimation(forKey: "ring")
        }
    }

    // MARK: - Coordinate helpers

    private func localPoint(fromView p: NSPoint) -> CGPoint {
        guard let root = layer else { return p }
        return contentLayer.convert(p, from: root)
    }

    private func screenPoint(fromLocal p: CGPoint) -> NSPoint {
        guard let root = layer, let window else { return p }
        let viewPoint = root.convert(p, from: contentLayer)
        return window.convertPoint(toScreen: convert(viewPoint, to: nil))
    }

    private var screenCenter: NSPoint {
        guard let frame = window?.frame else { return .zero }
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private func handle(atView p: NSPoint) -> Handle? {
        let local = localPoint(fromView: p)
        let slop = Metrics.knobHitSlop
        let knob = CGPoint(x: contentSize.width / 2, y: contentSize.height + Metrics.rotateKnobOffset)
        if hypot(local.x - knob.x, local.y - knob.y) <= slop { return .rotate }
        for corner in cornerPoints() where hypot(local.x - corner.x, local.y - corner.y) <= slop {
            return .corner(corner)
        }
        return nil
    }

    // MARK: - Opaque hit testing

    /// True when the screen point is over a visible (non-transparent) pixel of the pet,
    /// or over a handle while editing. Used to decide whether clicks pass through.
    func isInteractive(atScreenPoint sp: NSPoint) -> Bool {
        guard let window, let root = layer else { return false }
        let viewPoint = convert(window.convertPoint(fromScreen: sp), from: nil)
        if isEditing, handle(atView: viewPoint) != nil { return true }

        let p = imageLayer.convert(viewPoint, from: root)   // undoes the rotation
        let b = imageLayer.bounds
        guard b.contains(p) else { return false }
        if isEditing || videoLayer != nil { return true }
        guard let image = currentFrame else { return true }

        // Account for .resizeAspect letterboxing.
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let fit = min(b.width / iw, b.height / ih)
        let x = (p.x - (b.width - iw * fit) / 2) / fit
        let y = (p.y - (b.height - ih * fit) / 2) / fit
        guard x >= 0, x < iw, y >= 0, y < ih else { return false }
        return PetView.alpha(of: image, x: Int(x), yFromBottom: Int(y)) > Metrics.opaqueAlphaThreshold
    }

    private static func alpha(of image: CGImage, x: Int, yFromBottom: Int) -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(
                data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(image, in: CGRect(x: -x, y: -yFromBottom, width: image.width, height: image.height))
            return true
        }
        return drawn ? pixel[3] : 255
    }

    // MARK: - Mouse Events

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent)   { delegate?.petViewMouseMoved(self) }
    override func mouseEntered(with event: NSEvent) { delegate?.petViewMouseMoved(self) }
    override func mouseExited(with event: NSEvent)  { delegate?.petViewMouseMoved(self) }

    override func mouseDown(with event: NSEvent) {
        guard !clickThrough, let window else { return }
        window.makeFirstResponder(self)

        let viewPoint = convert(event.locationInWindow, from: nil)
        if isEditing, let hit = handle(atView: viewPoint) {
            switch hit {
            case .corner(let corner):
                let opposite = CGPoint(x: contentSize.width - corner.x, y: contentSize.height - corner.y)
                drag = .scale(fixed: screenPoint(fromLocal: opposite),
                              corner: screenPoint(fromLocal: corner),
                              startScale: scale)
            case .rotate:
                drag = .rotate(center: screenCenter)
            }
            return
        }

        guard !lockPosition else { return }
        drag = .move(startMouse: NSEvent.mouseLocation, startOrigin: window.frame.origin)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag, let window else { return }
        let mouse = NSEvent.mouseLocation

        switch drag {
        case .move(let startMouse, let startOrigin):
            window.setFrameOrigin(NSPoint(
                x: startOrigin.x + mouse.x - startMouse.x,
                y: startOrigin.y + mouse.y - startMouse.y
            ))

        case .scale(let fixed, let corner, let startScale):
            // Project the mouse onto the fixed→corner diagonal so the aspect ratio stays locked.
            let dx = corner.x - fixed.x, dy = corner.y - fixed.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 1 else { return }
            let projection = ((mouse.x - fixed.x) * dx + (mouse.y - fixed.y) * dy) / lengthSquared
            let newScale = clampScale(startScale * Double(projection))
            let ratio = CGFloat(newScale / startScale)
            let center = NSPoint(x: fixed.x + dx * ratio / 2, y: fixed.y + dy * ratio / 2)
            delegate?.petView(self, requestScale: newScale, center: center)

        case .rotate(let center):
            let dx = mouse.x - center.x, dy = mouse.y - center.y
            guard hypot(dx, dy) > 4 else { return }
            var degrees = atan2(dx, dy) * 180 / .pi   // clockwise from straight up
            if event.modifierFlags.contains(.shift) { degrees = (degrees / 15).rounded() * 15 }
            delegate?.petView(self, requestRotation: PetView.normalized(degrees))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard drag != nil else { return }
        drag = nil
        delegate?.petViewDidFinishDrag(self)
    }

    // MARK: - Scroll / Pinch / Keys

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command), !lockPosition else {
            super.scrollWheel(with: event)
            return
        }
        let step = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
        let factor = 1 + Double(event.scrollingDeltaY) * step
        guard factor > 0 else { return }
        delegate?.petView(self, requestScale: clampScale(scale * factor), center: nil)
    }

    override func magnify(with event: NSEvent) {
        guard !lockPosition else { return }
        delegate?.petView(self, requestScale: clampScale(scale * (1 + Double(event.magnification))), center: nil)
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !lockPosition else { super.keyDown(with: event); return }

        if flags.contains(.option), let key = event.specialKey, key == .leftArrow || key == .rightArrow {
            let step: Double = flags.contains(.shift) ? 1 : 5
            let delta = key == .rightArrow ? step : -step
            delegate?.petView(self, requestRotation: PetView.normalized(rotationDegrees + delta))
            return
        }

        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "=", "+": delegate?.petView(self, requestScale: clampScale(scale * 1.1), center: nil); return
            case "-":      delegate?.petView(self, requestScale: clampScale(scale / 1.1), center: nil); return
            case "0":      delegate?.petView(self, requestScale: clampScale(1.0), center: nil); return
            default: break
            }
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        delegate?.petViewContextMenu(self)
    }

    private func clampScale(_ value: Double) -> Double {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// Wrap any angle into -180...180.
    static func normalized(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    // MARK: - Drag & Drop Import

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURL(from: sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(from: sender) else { return false }
        delegate?.petView(self, didDropFileAt: url)
        return true
    }

    private func fileURL(from info: NSDraggingInfo) -> URL? {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let str  = item.string(forType: .fileURL),
              let url  = URL(string: str)
        else { return nil }
        let supported = ["gif","png","apng","mp4","mov","m4v"]
        return supported.contains(url.pathExtension.lowercased()) ? url : nil
    }

    // MARK: - Hit Testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        clickThrough ? nil : super.hitTest(point)
    }
}
