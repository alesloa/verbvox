import XCTest
import SwiftUI
import AppKit
@testable import VerbVoxCore

/// Constructs each view in an NSHostingController and forces a layout pass, so a
/// crash in any `body` (bad unwrap, etc.) fails here instead of only at click time.
@MainActor
final class ViewSmokeTests: XCTestCase {

    private func host<V: View>(_ view: V) {
        let controller = NSHostingController(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 580),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertNotNil(controller.view)
    }

    func testAllViewsConstruct() {
        let app = AppState()
        host(SettingsRootView().environmentObject(app))
        host(HomeView().environmentObject(app))
        host(RecordingView().environmentObject(app))
        host(WhisperView().environmentObject(app))
        host(AIPromptsView().environmentObject(app))
        host(DictionaryView().environmentObject(app))
        host(ProfanityView().environmentObject(app))
        host(HotkeysView().environmentObject(app))
        host(HistoryView().environmentObject(app))
        host(LogsView().environmentObject(app))
        host(AboutView().environmentObject(app))
        host(MenuBarView().environmentObject(app))
        host(OverlayIndicator(status: EngineStatus(
            phase: .recording, mode: "no_ai", lastTranscription: "", wpm: 0,
            timestamp: Date().timeIntervalSince1970)))
    }

    /// The built-in engine's status card, model picker and Home notice. Set on
    /// `config` directly so the real database is never written.
    func testBuiltinSourceViewsConstruct() {
        let app = AppState()
        app.config[ConfigCatalog.sttProviderKey] = "whisper_server"
        app.config[ConfigCatalog.serverModeKey] = "builtin"
        XCTAssertTrue(app.speechOnBuiltin)
        host(RecordingView().environmentObject(app))
        host(HomeView().environmentObject(app))
        host(MenuBarView().environmentObject(app))
        host(BuiltinStatusView().environmentObject(app))
    }
}
