// OverlayWindowController.swift
// Owns and manages one transparent overlay NSWindow.
// Coordinates between AppSettings, AnimationPlayer, VideoPlayer, and PetView.
//
// Window geometry: the window is the pet's rotated bounding box plus a transparent
// padding (room for edit handles). The pet center == window center == settings position.
// Clicks only land on the pet where its pixels are visible; everywhere else the window
// ignores mouse events so the app underneath gets the click.

import AppKit
import AVFoundation
import QuartzCore
import Combine

final class OverlayWindowController: NSWindowController {

    private enum LoadedAsset {
        case frameSequence(FrameSequence)
        case video(VideoPlayer)
    }

    private enum Constants {
        static let minScale = 0.1
        static let maxScale = 8.0
        static let videoNaturalSize = NSSize(width: 300, height: 300)
    }

    // MARK: - Dependencies
    let settings: AppSettings
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Callbacks
    var onOpenSettings: ((OverlayWindowController) -> Void)?

    // MARK: - Playback
    private let animationPlayer = AnimationPlayer()
    private var videoPlayer: VideoPlayer?

    // MARK: - Views
    private var petView: PetView!

    // MARK: - State
    private var currentAssetURL: URL?
    private var currentAssetIsSecurityScoped: Bool = false
    private var naturalSize: NSSize = NSSize(width: 200, height: 200)
    /// Center to use for the next layout triggered by a scale change (corner-handle resize).
    private var pendingCenter: NSPoint?
    /// The pet's exact center. Re-layouts (rotate, resize) keep it instead of re-reading window.frame:
    /// AppKit rounds window origins to whole points, and reading the center back after every
    /// 1° step made the pet creep toward the bottom-left while rotating.
    private var petCenter: NSPoint = .zero
    private var mouseMonitors: [Any] = []

    // MARK: - Init

    init(settings: AppSettings) {
        self.settings = settings

        let center = settings.savedPosition()
        petCenter = center
        let rect = NSRect(x: center.x - 100, y: center.y - 100, width: 200, height: 200)
        let window = OverlayWindow(contentRect: rect)
        window.acceptsMouseMovedEvents = true

        super.init(window: window)

        setupPetView()
        setupAnimationPlayer()
        applySettings()
        observeSettings()
        installMouseMonitors()
        layoutWindow(scale: settings.scale, rotation: settings.rotation, center: center)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        stopCurrentSecurityScopedAccess()
    }

    // MARK: - Setup

    private func setupPetView() {
        guard let window else { return }
        let view = PetView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.delegate = self
        window.contentView?.addSubview(view)
        self.petView = view
    }

    private func setupAnimationPlayer() {
        animationPlayer.delegate = self
        animationPlayer.speed = settings.speed
    }

    private func applySettings() {
        guard let window = window as? OverlayWindow else { return }
        window.setClickThrough(settings.clickThrough)
        window.setAlwaysOnTop(settings.alwaysOnTop)
        window.alphaValue = settings.opacity
        petView.lockPosition = settings.lockPosition
        petView.clickThrough = settings.clickThrough
        animationPlayer.speed = settings.speed
        if shouldAnimate { animationPlayer.play() }
    }

    // MARK: - Settings Observation

    private func observeSettings() {
        settings.$opacity.sink { [weak self] v in
            self?.window?.alphaValue = v
        }.store(in: &cancellables)

        // @Published emits in willSet, so use the emitted values, not settings.scale.
        settings.$scale.combineLatest(settings.$rotation).dropFirst().sink { [weak self] scale, rotation in
            guard let self else { return }
            let center = self.pendingCenter
            self.pendingCenter = nil
            self.layoutWindow(scale: scale, rotation: rotation, center: center)
        }.store(in: &cancellables)

        settings.$clickThrough.sink { [weak self] v in
            self?.petView.clickThrough = v
            DispatchQueue.main.async { self?.updateMouseInteraction() }
        }.store(in: &cancellables)

        settings.$lockPosition.sink { [weak self] v in
            self?.petView.lockPosition = v
            DispatchQueue.main.async { self?.updateMouseInteraction() }
        }.store(in: &cancellables)

        settings.$alwaysOnTop.sink { [weak self] v in
            (self?.window as? OverlayWindow)?.setAlwaysOnTop(v)
        }.store(in: &cancellables)

        settings.$speed.sink { [weak self] v in
            self?.animationPlayer.speed = v
            self?.videoPlayer?.speed = Float(v)
        }.store(in: &cancellables)

        // Also pause while nobody can see the screen (display asleep, locked, screen saver).
        settings.$playing.combineLatest(ScreenActivity.shared.$isVisible).sink { [weak self] playing, visible in
            guard let self else { return }
            if playing && visible { self.animationPlayer.play(); self.videoPlayer?.play() }
            else { self.animationPlayer.pause(); self.videoPlayer?.pause() }
        }.store(in: &cancellables)
    }

    private var shouldAnimate: Bool { settings.playing && ScreenActivity.shared.isVisible }

    // MARK: - Visibility

    /// Show or hide the overlay window without closing it.
    /// The animation continues running in the background while hidden.
    func setVisible(_ visible: Bool) {
        if visible {
            window?.orderFront(nil)
        } else {
            window?.orderOut(nil)
        }
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// The pet's rotated bounding box on screen (window frame minus the handle padding).
    var visualFrame: NSRect {
        let pad = PetView.Metrics.padding
        return (window?.frame ?? .zero).insetBy(dx: pad, dy: pad)
    }

    func setTalking(_ talking: Bool) {
        petView.setTalking(talking)
    }

    /// True while one of this pet's reminders is ringing (notification bubbles wait meanwhile).
    private(set) var isAlarmRinging = false

    /// `animate: false` keeps the alarm state (bubble still up) but stops the shaking.
    func setRinging(_ ringing: Bool, animate: Bool = true) {
        isAlarmRinging = ringing
        petView.setRinging(ringing && animate)
    }

    // MARK: - Asset Loading

    func loadAssetFromBookmark(_ bookmark: Data) -> Bool {
        guard let url = SecurityScopedAccess.resolve(bookmark: bookmark) else { return false }
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()

        let didLoad = loadAsset(
            url: url,
            // Not our own bookmark (made before the rename): save a fresh one.
            bookmarkData: didStartSecurityScope ? bookmark : SecurityScopedAccess.bookmark(for: url) ?? bookmark,
            preservingSecurityScope: didStartSecurityScope
        )
        if !didLoad, didStartSecurityScope {
            url.stopAccessingSecurityScopedResource()
        }

        return didLoad
    }

    /// Built-in pet used on first launch, before the user imports their own animation.
    func loadPlaceholder() {
        applyLoadedAsset(.frameSequence(PlaceholderAnimation.make()))
    }

    /// Switch this pet back to the built-in alarm-clock cat (forgets the imported file).
    func useDefaultPet() {
        loadPlaceholder()
        stopCurrentSecurityScopedAccess()
        currentAssetURL = nil
        settings.assetBookmark = nil   // no bookmark = built-in pet on next launch too
    }

    /// Stop accessing the current security-scoped resource if one is active.
    private func stopCurrentSecurityScopedAccess() {
        guard currentAssetIsSecurityScoped, let url = currentAssetURL else { return }
        url.stopAccessingSecurityScopedResource()
        currentAssetIsSecurityScoped = false
    }

    func loadAsset(url: URL) -> Bool {
        loadAsset(url: url, bookmarkData: SecurityScopedAccess.bookmark(for: url), preservingSecurityScope: false)
    }

    private func loadAsset(url: URL, bookmarkData: Data?, preservingSecurityScope: Bool) -> Bool {
        guard let loadedAsset = decodeAsset(url: url) else { return false }

        let previousAssetURL = currentAssetURL
        let previousAssetWasSecurityScoped = currentAssetIsSecurityScoped

        applyLoadedAsset(loadedAsset)

        currentAssetURL = url
        currentAssetIsSecurityScoped = preservingSecurityScope
        settings.assetBookmark = bookmarkData

        if previousAssetWasSecurityScoped,
           let previousAssetURL,
           previousAssetURL != url {
            previousAssetURL.stopAccessingSecurityScopedResource()
        }

        return true
    }

    private func decodeAsset(url: URL) -> LoadedAsset? {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "gif":
            return GIFDecoder.decode(url: url).map(LoadedAsset.frameSequence)
        case "png", "apng":
            return APNGDecoder.decode(url: url).map(LoadedAsset.frameSequence)
        case "mp4", "mov", "m4v", "avi", "mkv":
            return VideoPlayer(url: url).map(LoadedAsset.video)
        default:
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return PNGSequenceDecoder.decode(directory: url).map(LoadedAsset.frameSequence)
            }
            return APNGDecoder.decode(url: url).map(LoadedAsset.frameSequence)
        }
    }

    private func applyLoadedAsset(_ loadedAsset: LoadedAsset) {
        switch loadedAsset {
        case .frameSequence(let sequence):
            removeVideoLayer()
            if let first = sequence.frames.first {
                naturalSize = NSSize(width: CGFloat(first.width), height: CGFloat(first.height))
            }
            animationPlayer.load(sequence)
            if shouldAnimate { animationPlayer.play() }

        case .video(let player):
            animationPlayer.stop()
            removeVideoLayer()
            videoPlayer = player
            player.speed = Float(settings.speed)
            naturalSize = Constants.videoNaturalSize
            petView.setVideoLayer(player.playerLayer)
            if shouldAnimate { player.play() }
        }

        // A new asset may have a different natural size — keep the scale on-screen.
        let clamped = clampScale(settings.scale)
        if clamped != settings.scale {
            settings.scale = clamped   // triggers layout via the sink
        } else {
            layoutWindow(scale: settings.scale, rotation: settings.rotation, center: nil)
        }
    }

    private func removeVideoLayer() {
        guard videoPlayer != nil else { return }
        petView.setVideoLayer(nil)
        videoPlayer = nil
    }

    // MARK: - Window Sizing

    /// Largest scale that still fits the pet on the current screen.
    private var scaleRange: ClosedRange<Double> {
        let screen = (window?.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let fit = min(screen.width / naturalSize.width, screen.height / naturalSize.height)
        let upper = min(Constants.maxScale, Double(fit))
        return min(Constants.minScale, upper)...upper
    }

    private func clampScale(_ value: Double) -> Double {
        let range = scaleRange
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func layoutWindow(scale: Double, rotation: Double, center: NSPoint?) {
        guard let window else { return }
        // The settings slider goes up to 8×; never draw bigger than the screen allows.
        let scale = clampScale(scale)

        let w = naturalSize.width * scale
        let h = naturalSize.height * scale
        let radians = rotation * .pi / 180
        let cosA = abs(cos(radians)), sinA = abs(sin(radians))
        let boxW = w * cosA + h * sinA
        let boxH = w * sinA + h * cosA

        let pad = PetView.Metrics.padding
        let size = NSSize(width: ceil(boxW + pad * 2), height: ceil(boxH + pad * 2))
        let c = center ?? petCenter
        petCenter = c
        window.setFrame(NSRect(x: c.x - size.width / 2, y: c.y - size.height / 2,
                               width: size.width, height: size.height),
                        display: true, animate: false)

        petView.scale = scale
        petView.scaleRange = scaleRange
        petView.contentSize = CGSize(width: w, height: h)
        petView.rotationDegrees = rotation
    }

    // MARK: - Mouse pass-through / edit mode

    private func installMouseMonitors() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .flagsChanged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.updateMouseInteraction()
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.updateMouseInteraction()
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    /// Decide whether the window should receive the mouse right now, and whether
    /// the ⌥ edit handles should be visible.
    func updateMouseInteraction() {
        guard let window, window.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let inside = window.frame.contains(mouse)

        let canEdit = !settings.lockPosition && !settings.clickThrough
        petView.isEditing = canEdit && inside && NSEvent.modifierFlags.contains(.option)

        let interactive = !settings.clickThrough && inside && petView.isInteractive(atScreenPoint: mouse)
        if window.ignoresMouseEvents == interactive {
            window.ignoresMouseEvents = !interactive
        }
    }
}

// MARK: - AnimationPlayerDelegate

extension OverlayWindowController: AnimationPlayerDelegate {
    func animationPlayer(_ player: AnimationPlayer, didAdvanceTo frame: CGImage) {
        petView.display(frame: frame)
    }
}

// MARK: - PetViewDelegate

extension OverlayWindowController: PetViewDelegate {
    func petView(_ view: PetView, didDropFileAt url: URL) {
        _ = loadAsset(url: url)
    }

    func petViewDidFinishDrag(_ view: PetView) {
        guard let window else { return }
        // Only a real move changes the center; after a zoom step the frame differs just by rounding.
        let frameCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        if hypot(frameCenter.x - petCenter.x, frameCenter.y - petCenter.y) > 1 { petCenter = frameCenter }
        settings.savePosition(petCenter)
    }

    func petView(_ view: PetView, requestScale scale: Double, center: NSPoint?) {
        pendingCenter = center
        settings.scale = clampScale(scale)
        if center == nil { petViewDidFinishDrag(view) }
    }

    func petView(_ view: PetView, requestRotation degrees: Double) {
        settings.rotation = degrees
    }

    func petViewMouseMoved(_ view: PetView) {
        updateMouseInteraction()
    }

    func petViewContextMenu(_ view: PetView) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "각도 초기화 (0°)", action: #selector(resetRotation), keyEquivalent: "").target = self
        menu.addItem(withTitle: "크기 초기화 (100%)", action: #selector(resetScale), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "설정…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "숨기기", action: #selector(hidePet), keyEquivalent: "").target = self
        menu.addItem(.separator())
        let awakeItem = SleepGuard.shared.menuItem(action: #selector(toggleKeepAwake))
        awakeItem.target = self
        menu.addItem(awakeItem)
        return menu
    }

    @objc private func toggleKeepAwake() { SleepGuard.shared.toggleFromMenu() }

    @objc private func resetRotation() { settings.rotation = 0 }
    @objc private func resetScale()    { settings.scale = clampScale(1.0) }
    @objc private func openSettings()  { onOpenSettings?(self) }
    @objc private func hidePet()       { setVisible(false) }
}
