import AppKit
import SwiftUI

/// Manages a borderless floating panel that shows the recording/processing HUD.
@MainActor
final class OverlayController {
    private var panel: NSPanel?

    func update(_ status: EngineStatus) {
        switch status.phase {
        case .recording, .processing:
            show(status)
        default:
            hide()
        }
    }

    private func show(_ status: EngineStatus) {
        let hosting = NSHostingView(rootView: OverlayIndicator(status: status))
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let p = panel ?? makePanel()
        panel = p
        p.contentView = hosting

        if let screen = NSScreen.main {
            let x = screen.frame.midX - size.width / 2
            let y = screen.frame.minY + 120
            p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        p.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 56),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovable = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}
