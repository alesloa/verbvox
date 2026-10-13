import AppKit
import SwiftUI

/// Manages the main settings/dashboard window as an AppKit `NSWindow` so it does
/// not auto-open at launch (a menu-bar app should start with no window).
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(app: AppState) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsRootView().environmentObject(app))
            let w = NSWindow(contentViewController: hosting)
            w.title = "VerbVox"
            w.setContentSize(NSSize(width: 880, height: 580))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.minSize = NSSize(width: 740, height: 480)
            w.center()
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Return to a pure menu-bar app (no Dock icon) when the window closes.
        NSApp.setActivationPolicy(.accessory)
    }
}
