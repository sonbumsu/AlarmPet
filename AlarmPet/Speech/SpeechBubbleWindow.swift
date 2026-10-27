// SpeechBubbleWindow.swift
// A separate transparent panel for the bubble, so it never rotates with the pet
// and is never clipped by the pet window. Follows the pet when it moves/resizes,
// flips below the pet near the top of the screen, and stays inside the screen.
// Content is pluggable: notification bubbles (SpeechBubbleView) and alarms (AlarmBubbleView).

import AppKit
import SwiftUI

final class SpeechBubbleWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The bubble panel never becomes key, so its buttons must react to the very first click.
final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Where the tail points right now; bubble views draw their tail from it.
struct BubbleLayout {
    var tailOnBottom: Bool
    var tailX: CGFloat
    var animated: Bool
}

final class SpeechBubbleController {

    var onTap: (() -> Void)?

    private let window = SpeechBubbleWindow()
    private var hosting: FirstMouseHostingView?
    private weak var pet: OverlayWindowController?
    private var content: ((BubbleLayout) -> AnyView)?
    private var maxViewWidth: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    /// Bumped on every show/hide so a stale fade-out never hides a newer bubble.
    private var generation = 0

    deinit {
        detach()
        window.orderOut(nil)   // don't leave an invisible panel behind if we go away mid-fade
    }

    // MARK: - Show / Hide

    func show(_ message: PetMessage, on pet: OverlayWindowController) {
        let size = CGFloat(pet.settings.bubbleSize)
        present(on: pet, maxViewWidth: SpeechBubbleView.Metrics.maxViewWidth(size: size)) { [weak self] layout in
            AnyView(SpeechBubbleView(message: message, tailOnBottom: layout.tailOnBottom, tailX: layout.tailX,
                                     animated: layout.animated, size: size) { self?.onTap?() })
        }
    }

    /// Show any bubble-shaped view above the pet. `content` is re-evaluated when the tail moves.
    func present(on pet: OverlayWindowController, maxViewWidth: CGFloat, content: @escaping (BubbleLayout) -> AnyView) {
        generation += 1
        attach(to: pet)
        self.content = content
        self.maxViewWidth = maxViewWidth

        let view = FirstMouseHostingView(rootView: content(BubbleLayout(tailOnBottom: true, tailX: 0, animated: true)))
        view.sizingOptions = []   // we size the window ourselves in reposition()
        window.contentView = view
        hosting = view

        reposition()
        window.alphaValue = 1
        window.orderFrontRegardless()
    }

    func hide() {
        generation += 1
        let token = generation
        detach()
        content = nil
        let window = self.window
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Order out unless a newer show() reused the panel meanwhile.
            guard self == nil || self?.generation == token else { return }
            window.orderOut(nil)
        })
    }

    // MARK: - Following the pet

    private func attach(to pet: OverlayWindowController) {
        guard self.pet !== pet else { return }
        detach()
        self.pet = pet
        guard let petWindow = pet.window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(center.addObserver(forName: name, object: petWindow, queue: .main) { [weak self] _ in
                self?.reposition()
            })
        }
    }

    private func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        pet = nil
    }

    private func reposition() {
        guard let pet, let content, let hosting else { return }
        let petFrame = pet.visualFrame
        let screen = (pet.window?.screen ?? NSScreen.main)?.visibleFrame ?? petFrame
        let margin = SpeechBubbleView.Metrics.margin
        let gap: CGFloat = 2

        // Round up (+1pt slack): a fractional width rounded down makes the text wrap
        // in the real window and no longer match the measured height.
        // fittingSize measures the text on one line; long text needs a second pass at max width to wrap.
        let probe = NSHostingController(rootView: content(BubbleLayout(tailOnBottom: true, tailX: 0, animated: false)))
        var fitting = probe.view.fittingSize
        if fitting.width >= maxViewWidth - 0.5 {
            fitting = probe.sizeThatFits(in: NSSize(width: maxViewWidth, height: 10_000))
        }
        let size = NSSize(width: ceil(fitting.width) + 1, height: ceil(fitting.height))

        // Prefer above the pet; flip below when there's no room.
        var tailOnBottom = true
        var y = petFrame.maxY + gap - margin
        if y + size.height > screen.maxY {
            tailOnBottom = false
            y = petFrame.minY - gap + margin - size.height
        }
        y = min(max(y, screen.minY), screen.maxY - size.height)

        var x = petFrame.midX - size.width / 2
        x = min(max(x, screen.minX), screen.maxX - size.width)

        let tailX = petFrame.midX - x - margin
        hosting.rootView = content(BubbleLayout(tailOnBottom: tailOnBottom, tailX: tailX, animated: true))
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
