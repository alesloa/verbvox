import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Text(statusLine)

        Divider()

        if app.engine.engineRunning {
            Button("Stop Engine") { app.stopEngine() }
            Button("Restart Engine") { app.restartEngine() }
        } else {
            Button(app.engine.busy ? "Starting…" : "Start Engine") { app.startEngine() }
                .disabled(app.engine.busy)
        }

        // Whisper server power, via the external whisperctl supervisor. Hidden for
        // cloud STT providers and the built-in engine, which have no server of the
        // user's to switch on or off.
        if app.engine.sttIsWhisperServer, !app.builtinChosen {
            Divider()

            if app.engine.serverRunning, !app.builtinCovering {
                Button(app.serverControlBusy ? "Stopping server…" : "Stop Whisper Server") {
                    app.stopWhisperServer()
                }
                .disabled(app.serverControlBusy)
            } else {
                Button(app.serverControlBusy ? "Starting server…" : "Start Whisper Server") {
                    app.startWhisperServer()
                }
                .disabled(app.serverControlBusy)
            }

            if let err = app.serverControlError {
                Text(err)
            }
        }

        Divider()

        Button("Settings…") { app.showSettings() }
            .keyboardShortcut(",", modifiers: .command)
        Button("History") { app.showSettings(.history) }
        Button("Dictionary") { app.showSettings(.dictionary) }

        Divider()

        Button("Quit VerbVox") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private var statusLine: String {
        if !app.engine.engineRunning && app.status.phase == .stopped {
            return "● Engine stopped"
        }
        switch app.status.phase {
        case .recording:
            return app.status.mode == "with_ai" ? "🔴 Recording (AI)" : "🔴 Recording"
        case .processing:
            return "⚙ Transcribing…"
        case .idle:
            if app.speechOnBuiltin {
                let status = app.builtin.status
                switch status.phase {
                case .ready: return "🟢 Ready"
                case .downloading: return "🟡 Downloading speech model (\(status.downloadPercent)%)"
                case .failed: return "🟡 Speech engine stopped"
                default: return "🟡 Starting speech engine…"
                }
            }
            // Cloud STT has no local server to be "off", so only warn when the
            // whisper server is the selected provider and it isn't answering.
            if !app.engine.sttIsWhisperServer || app.engine.serverRunning {
                return "🟢 Ready"
            }
            return "🟡 Ready (server off)"
        default:
            return "● Engine stopped"
        }
    }
}
