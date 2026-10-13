import SwiftUI
import AppKit
import ApplicationServices

/// Menu-bar app entry. The settings window is managed in AppKit (see
/// SettingsWindowController) so nothing opens at launch.
public struct VerbVoxRootApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(app)
        } label: {
            Image(systemName: menuSymbol)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuSymbol: String {
        switch app.status.phase {
        case .recording: return "waveform.badge.mic"
        case .processing: return "gearshape"
        default: return "waveform"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start as a pure menu-bar app (no Dock icon, no window).
        NSApp.setActivationPolicy(.accessory)

        // Paste is driven by synthetic ⌘V CGEvents, which macOS silently drops
        // unless the app is trusted for Accessibility. There is no implicit
        // prompt when posting events, so ask explicitly on launch: this shows the
        // system "grant in Privacy & Security" prompt when not yet trusted, and is
        // a no-op once granted. Without it the user has to find the pane manually.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
