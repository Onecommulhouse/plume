import AppKit
import SwiftUI

/// Petite pilule flottante en bas de l'écran pendant la dictée, avec au-dessus le texte entendu en direct.
/// Elle ne prend jamais le focus, pour que le texte arrive bien dans l'app où l'on écrit.
@MainActor
final class OverlayController {
    private let panel: NSPanel
    static let size = NSSize(width: 580, height: 200)

    init(controller: DictationController) {
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: OverlayView().environmentObject(controller))
        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        panel.contentView = hosting
    }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 48))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct OverlayView: View {
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        VStack(spacing: 10) {
            if showsBubble {
                LiveTextBubble(text: Self.tail(of: controller.liveText), dimmed: controller.phase != .recording)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            pill
        }
        .frame(width: OverlayController.size.width, height: OverlayController.size.height, alignment: .bottom)
        .animation(.easeOut(duration: 0.18), value: showsBubble)
    }

    private var showsBubble: Bool {
        guard !controller.liveText.isEmpty else { return false }
        switch controller.phase {
        case .recording, .transcribing, .cleaning: return true
        default: return false
        }
    }

    private var pill: some View {
        HStack(spacing: 12) {
            switch controller.phase {
            case .recording:
                if controller.isHandsFree {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.mustard)
                } else {
                    Circle().fill(Theme.mustard).frame(width: 8, height: 8)
                }
                LiveWave(levels: controller.levels)
                    .frame(width: controller.isHandsFree ? 96 : 120, height: 26)
                if let target = controller.translateTarget {
                    Text(target.badge)
                        .font(Theme.font(10, .bold))
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.mustard))
                }
                if controller.isHandsFree, let start = controller.recordingStartedAt {
                    TimelineView(.periodic(from: start, by: 1)) { context in
                        Text(Self.elapsed(from: start, to: context.date))
                            .font(Theme.font(12, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.paper)
                    }
                }
            case .transcribing, .cleaning:
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.mustard)
                Text(processingLabel)
                    .font(Theme.font(13, .semibold))
                    .foregroundStyle(Theme.paper)
            case .error(let message):
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.mustard)
                Text(message)
                    .font(Theme.font(12, .semibold))
                    .foregroundStyle(Theme.paper)
                    .lineLimit(2)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Theme.navy)
                .overlay(Capsule().strokeBorder(Theme.mustard.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        )
        .frame(width: 260, height: 64)
        .animation(.easeOut(duration: 0.12), value: controller.levels)
    }

    private var processingLabel: String {
        guard controller.phase == .cleaning else { return "Plume écrit…" }
        if let language = controller.activeTranslation {
            return "Traduction en \(language.promptName)…"
        }
        return "Mise au propre…"
    }

    /// Garde la fin du texte (les derniers mots dits), pour que la bulle reste sur trois lignes.
    static func tail(of text: String, limit: Int = 170) -> String {
        guard text.count > limit else { return text }
        let cut = text.suffix(limit)
        if let space = cut.firstIndex(of: " ") {
            return "… " + cut[cut.index(after: space)...]
        }
        return "… " + cut
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Bulle au-dessus de la pilule : ce que Plume entend, mot après mot.
struct LiveTextBubble: View {
    let text: String
    let dimmed: Bool

    var body: some View {
        Text(text)
            .font(Theme.font(14, .medium))
            .foregroundStyle(Theme.paper.opacity(dimmed ? 0.7 : 1))
            .lineSpacing(3)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: 540)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.navy.opacity(0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.mustard.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            )
            .animation(.easeOut(duration: 0.15), value: text)
    }
}

struct LiveWave: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Theme.mustard)
                        .frame(height: max(3, geo.size.height * level))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
