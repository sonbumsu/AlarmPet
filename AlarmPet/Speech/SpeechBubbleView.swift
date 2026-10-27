// SpeechBubbleView.swift
// The speech bubble drawn above (or below) the pet.
//
//   집가고싶어ㅠㅠ                 ← body, large (up to 3 lines)
//   [icon] 카카오톡       - 손범수  ← footer, small grey: app on the left, sender on the right

import SwiftUI
import AppKit

struct SpeechBubbleView: View {

    /// Sizes at 100%. Everything except `margin` is multiplied by the bubble size setting.
    enum Metrics {
        static let fontSize: CGFloat = 14
        static let footerFontSize: CGFloat = 11
        static let footerSpacing: CGFloat = 4
        static let maxTextWidth: CGFloat = 280
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let tailHeight: CGFloat = 10
        static let tailWidth: CGFloat = 16
        static let cornerRadius: CGFloat = 12
        /// Transparent margin around the bubble so the shadow isn't clipped.
        static let margin: CGFloat = 10

        /// Widest the whole view (bubble + margin) can get at a given size.
        static func maxViewWidth(size: CGFloat) -> CGFloat {
            (maxTextWidth + horizontalPadding * 2) * size + margin * 2
        }
    }

    let message: PetMessage
    var tailOnBottom: Bool = true
    /// Tail tip x, measured from the bubble shape's leading edge.
    var tailX: CGFloat = 0
    var animated: Bool = true
    /// Bubble size multiplier (1 = 100%).
    var size: CGFloat = 1
    var onTap: () -> Void = {}

    @StateObject private var appearance = AppearanceModel()

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.footerSpacing * size) {
            Text(styledBody)
                .font(.system(size: Metrics.fontSize * size))
                .lineLimit(3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            footer
        }
            .frame(maxWidth: Metrics.maxTextWidth * size, alignment: .leading)
            .padding(.horizontal, Metrics.horizontalPadding * size)
            .padding(.vertical, Metrics.verticalPadding * size)
            .padding(tailOnBottom ? .bottom : .top, Metrics.tailHeight * size)
            .background(
                BubbleShape(tailOnBottom: tailOnBottom, tailX: tailX, size: size)
                    .fill(Color(nsColor: SpeechBubbleView.bubbleColor))
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
            )
            .padding(Metrics.margin)
            .scaleEffect(appearance.appeared || !animated ? 1 : 0.8, anchor: tailOnBottom ? .bottom : .top)
            .opacity(appearance.appeared || !animated ? 1 : 0)
            .onAppear {
                guard animated else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { appearance.appeared = true }
            }
            .onTapGesture(perform: onTap)
    }

    /// Discord/Slack send inline markdown (**굵게**, _기울임_) — show it styled instead of raw asterisks.
    private var styledBody: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.body, options: options)) ?? AttributedString(message.body)
    }

    private var footer: some View {
        HStack(spacing: Metrics.footerSpacing * size) {
            if let icon = AppIcons.icon(for: message.sourceApp ?? message.app) ?? AppIcons.icon(for: message.app) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: (Metrics.footerFontSize + 2) * size, height: (Metrics.footerFontSize + 2) * size)
            }
            Text(message.app)
                .fontWeight(.semibold)
                .lineLimit(1)
                .layoutPriority(1)
            if let sender = message.sender, !sender.isEmpty {
                Spacer(minLength: 12 * size)
                Text("- \(sender)")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: Metrics.footerFontSize * size))
        .foregroundStyle(.secondary)
    }

    static let bubbleColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.18, alpha: 1)
            : NSColor.white
    }
}

/// Looks up the icon of the app a notification came from (cached; nil if not found).
enum AppIcons {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for appName: String) -> NSImage? {
        if let cached = cache[appName] { return cached }
        let found = lookup(appName)
        cache[appName] = found
        return found
    }

    private static func lookup(_ name: String) -> NSImage? {
        AppDirectory.url(for: name).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

/// ObservableObject instead of @State (no SwiftUI macro plugin in Command Line Tools).
private final class AppearanceModel: ObservableObject {
    @Published var appeared = false
}

/// Rounded rectangle with a small triangular tail pointing at the pet.
struct BubbleShape: Shape {
    var tailOnBottom: Bool
    var tailX: CGFloat
    var size: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let m = SpeechBubbleView.Metrics.self
        let tailHeight = m.tailHeight * size
        let radius = m.cornerRadius * size
        let body = tailOnBottom
            ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)
            : CGRect(x: rect.minX, y: rect.minY + tailHeight, width: rect.width, height: rect.height - tailHeight)

        var path = Path(roundedRect: body, cornerRadius: radius)

        let half = m.tailWidth * size / 2
        let x = min(max(rect.minX + tailX, rect.minX + radius + half),
                    rect.maxX - radius - half)
        let baseY = tailOnBottom ? body.maxY : body.minY
        let tipY  = tailOnBottom ? rect.maxY : rect.minY

        path.move(to: CGPoint(x: x - half, y: baseY))
        path.addLine(to: CGPoint(x: x, y: tipY))
        path.addLine(to: CGPoint(x: x + half, y: baseY))
        path.closeSubpath()
        return path
    }
}
