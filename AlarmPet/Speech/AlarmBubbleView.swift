// AlarmBubbleView.swift
// The bubble shown while a reminder is ringing.
//
//   ⏰ 07:30                     ← time (orange)
//   일어나기                      ← reminder title, large
//   [5분 뒤 다시]  [끄기]

import SwiftUI
import AppKit

struct AlarmBubbleView: View {

    private enum Metrics {
        static let titleFontSize: CGFloat = 17
        static let captionFontSize: CGFloat = 11
        static let buttonFontSize: CGFloat = 12
        static let minWidth: CGFloat = 190
    }

    let reminder: PetReminder
    var layout: BubbleLayout
    /// Bubble size multiplier (the pet's bubble size setting).
    var size: CGFloat = 1
    /// After the ringing times out the bubble stays, marked as missed.
    var missed: Bool = false
    var onSnooze: () -> Void
    var onStop: () -> Void

    @StateObject private var motion = AlarmMotion()

    var body: some View {
        let m = SpeechBubbleView.Metrics.self
        VStack(alignment: .leading, spacing: 6 * size) {
            HStack(spacing: 4 * size) {
                Image(systemName: missed ? "alarm" : "alarm.fill")
                Text(missed ? "\(reminder.timeText) · 놓친 알람" : reminder.timeText)
            }
            .font(.system(size: Metrics.captionFontSize * size, weight: .semibold))
            .foregroundStyle(.orange)

            Text(reminder.title.isEmpty ? "알람" : reminder.title)
                .font(.system(size: Metrics.titleFontSize * size, weight: .bold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8 * size) {
                Button("5분 뒤 다시", action: onSnooze)
                    .buttonStyle(AlarmButtonStyle(prominent: false, size: size))
                Button("끄기", action: onStop)
                    .buttonStyle(AlarmButtonStyle(prominent: true, size: size))
            }
            .padding(.top, 2 * size)
        }
        .frame(minWidth: Metrics.minWidth * size, maxWidth: m.maxTextWidth * size, alignment: .leading)
        .padding(.horizontal, m.horizontalPadding * size + 2)
        .padding(.vertical, m.verticalPadding * size + 2)
        .padding(layout.tailOnBottom ? .bottom : .top, m.tailHeight * size)
        .background(
            BubbleShape(tailOnBottom: layout.tailOnBottom, tailX: layout.tailX, size: size)
                .fill(Color(nsColor: SpeechBubbleView.bubbleColor))
                .shadow(color: .orange.opacity(glowOpacity), radius: 7)
                // Scoped to the background: a repeatForever started with withAnimation in onAppear
                // also catches the first layout pass, and the text/buttons would wobble forever.
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: motion.pulse)
        )
        .padding(m.margin)
        // The bubble itself stays still (easy to read and click); only the glow breathes.
        .onAppear {
            guard layout.animated, !missed else { return }
            DispatchQueue.main.async { motion.pulse = true }
        }
    }

    private var glowOpacity: Double {
        if missed { return 0.25 }
        return motion.pulse ? 0.8 : 0.35
    }

    /// Room for the bubble at its widest (used to measure wrapping).
    static func maxViewWidth(size: CGFloat) -> CGFloat {
        let m = SpeechBubbleView.Metrics.self
        return (m.maxTextWidth + (m.horizontalPadding + 2) * 2) * size + m.margin * 2
    }
}

/// ObservableObject instead of @State (no SwiftUI macro plugin in Command Line Tools).
private final class AlarmMotion: ObservableObject {
    @Published var pulse = false
}

/// Capsule buttons that scale with the bubble size.
private struct AlarmButtonStyle: ButtonStyle {
    let prominent: Bool
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12 * size, weight: .semibold))
            .padding(.horizontal, 12 * size)
            .padding(.vertical, 5 * size)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                Capsule().fill(prominent ? Color.orange : Color.secondary.opacity(0.18))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
