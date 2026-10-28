// AnimationPlayer.swift
// Central playback controller for frame-based animations (GIF/APNG/PNG sequence).
//
// Uses a one-shot timer that is re-armed for the moment the next frame is due:
// - Wakes only when the frame actually changes (a 15 fps GIF wakes 15×/s, not 120×/s)
// - Sleeps the thread between frames — no busy-wait
//
// Only updates CALayer.contents when the frame index actually changes,
// so the GPU compositor is not disturbed on frames where nothing changes.
//
// Thread safety:
// - The timer fires on a private serial queue.
// - The main thread calls load/play/pause/stop.
// - `playbackState` (time, lastFrameIndex, lastHostTime) and `sequence` are
//   accessed from both threads, so they are protected by `stateLock`.

import QuartzCore
import CoreGraphics
import Foundation
import os

@MainActor
protocol AnimationPlayerDelegate: AnyObject {
    func animationPlayer(_ player: AnimationPlayer, didAdvanceTo frame: CGImage)
}

final class AnimationPlayer {

    // MARK: - Public
    weak var delegate: AnimationPlayerDelegate?

    var speed: Double = 1.0 {
        didSet { speed = max(0.1, min(speed, 8.0)) }
    }

    private(set) var isPlaying: Bool = false

    // MARK: - Lock-protected state
    //
    // These properties are read/written from both the main thread and the
    // timer queue. Access them only while holding `stateLock`.

    private var stateLock = OSAllocatedUnfairLock(initialState: PlaybackState())

    private struct PlaybackState {
        var sequence: FrameSequence? = nil
        var playbackTime: TimeInterval = 0
        var lastHostTime: TimeInterval = 0
        var lastFrameIndex: Int = -1
    }

    // MARK: - Main-thread-only state
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "NotiPet.AnimationPlayer", qos: .userInteractive)

    private enum Constants {
        /// Never re-arm sooner than this (a broken GIF with 0 s delays would spin).
        static let minimumWait: TimeInterval = 1.0 / 60
        /// Lets the system coalesce wakeups; far below what the eye notices.
        static let leeway: DispatchTimeInterval = .milliseconds(3)
    }

    // MARK: - Load

    @MainActor
    func load(_ sequence: FrameSequence) {
        let wasPlaying = isPlaying
        stop()
        stateLock.withLock { state in
            state.sequence = sequence
            state.playbackTime = 0
            state.lastFrameIndex = -1
            state.lastHostTime = 0
        }

        // Show first frame immediately on main thread
        if let first = sequence.frames.first {
            delegate?.animationPlayer(self, didAdvanceTo: first)
        }

        if wasPlaying { play() }
    }

    // MARK: - Playback Control

    func play() {
        guard !isPlaying else { return }
        let hasSequence = stateLock.withLock { $0.sequence != nil }
        guard hasSequence else { return }
        isPlaying = true
        stateLock.withLock { $0.lastHostTime = 0 }   // don't count the paused time
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        stopTimer()
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func stop() {
        pause()
        stateLock.withLock { state in
            state.playbackTime = 0
            state.lastFrameIndex = -1
            state.lastHostTime = 0
        }
    }

    // MARK: - Timer

    private func startTimer() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.setEventHandler { [weak self, weak timer] in
            if let timer { self?.tick(rearming: timer) }
        }
        timer.schedule(deadline: .now(), leeway: Constants.leeway)
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Tick (fires on timerQueue, NOT main thread)

    private func tick(rearming timer: DispatchSourceTimer) {
        let hostTime = CACurrentMediaTime()
        let speed = self.speed

        // All shared state is accessed under the lock.
        let result: (frame: CGImage?, wait: TimeInterval)? = stateLock.withLock { state in
            guard let sequence = state.sequence, sequence.count > 0 else { return nil }

            let delta = state.lastHostTime > 0 ? hostTime - state.lastHostTime : 0
            state.lastHostTime = hostTime
            state.playbackTime += delta * speed

            let wait = sequence.timeUntilNextFrame(at: state.playbackTime) / speed
            let newIndex = sequence.frameIndex(at: state.playbackTime)
            guard newIndex != state.lastFrameIndex else { return (nil, wait) }
            state.lastFrameIndex = newIndex
            return (sequence.frames[newIndex], wait)
        }

        guard let result else { return }
        // A single-frame image never changes: no need to wake again.
        if result.wait.isFinite {
            timer.schedule(deadline: .now() + max(result.wait, Constants.minimumWait), leeway: Constants.leeway)
        }

        guard let frame = result.frame else { return }
        // Dispatch to main thread for CALayer update
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.animationPlayer(self, didAdvanceTo: frame)
        }
    }

    // MARK: - Deinit

    deinit {
        timer?.cancel()
    }
}
