import SwiftUI

struct AboutView: View {
    @EnvironmentObject var app: AppState

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return v
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "waveform")
                        .font(.system(size: 34)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VerbVox").font(.title2.weight(.semibold))
                        Text("Version \(version)").foregroundStyle(.secondary)
                        Text("A native front-end for your whisper.cpp engine.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Backend") {
                LabeledContent("Status") {
                    StatusDot(color: app.dbAvailable ? .green : .red,
                              text: app.dbAvailable ? "Database connected" : "Not found")
                }
                LabeledContent("Folder") {
                    Text(app.paths.root.path).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Change backend folder…") { app.chooseBackendFolder() }
                LabeledContent("Python") {
                    Text(app.paths.python).font(.caption).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Engine") {
                LabeledContent("Whisper server") {
                    if app.engine.sttIsWhisperServer {
                        StatusDot(color: app.engine.serverRunning ? .green : .secondary,
                                  text: app.engine.serverRunning ? "Reachable" : "Unreachable")
                    } else {
                        StatusDot(color: .secondary, text: "N/A — cloud STT")
                    }
                }
                LabeledContent("Recorder") {
                    StatusDot(color: app.engine.engineRunning ? .green : .secondary,
                              text: app.engine.engineRunning ? "Running" : "Stopped")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}
