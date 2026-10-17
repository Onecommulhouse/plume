import AppKit
import SwiftUI

/// Petite pilule flottante en bas de l'écran pendant la dictée. Elle ne prend jamais le focus,
/// pour que le texte arrive bien dans l'app où l'on écrit.
@MainActor
final class OverlayController {
    private let panel: NSPanel

    init(controller: DictationController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 64),
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
        HStack(spacing: 12) {
            switch controller.phase {
            case .recording:
                Circle().fill(Theme.mustard).frame(width: 8, height: 8)
                LiveWave(levels: controller.levels)
                    .frame(width: 120, height: 26)
            case .transcribing, .cleaning:
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.mustard)
                Text(controller.phase == .cleaning ? "Mise au propre…" : "Plume écrit…")
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
