import SwiftUI

/// The user's own whisper server: power, loaded model, and which models are on disk.
///
/// Everything here goes through the external `whisperctl` supervisor; the built-in
/// engine lives in the Recording tab. Picking a model hot-swaps it on a running server, so a
/// switch costs no downtime. Transcription settings (provider, URL, local vs
/// remote) stay in the Recording tab; this tab is only about the server itself.
struct WhisperView: View {
    @EnvironmentObject var app: AppState

    private var controlURLBinding: Binding<String> {
        Binding(
            get: { app.whisperControlURL },
            set: { app.setStr(ConfigCatalog.controlURLKey, $0, category: "whisper_server") })
    }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Status") { statusDot }

                if app.whisperPanelReachable, app.whisperPanel.running {
                    LabeledContent("Address", value: app.whisperPanel.whisperURL)
                    LabeledContent("Process") {
                        Text(processDetail).monospacedDigit()
                    }
                }

                HStack {
                    Button("Start") { app.startWhisperServer() }
                        .disabled(busy || app.whisperPanel.running)
                    Button("Stop") { app.stopWhisperServer() }
                        .disabled(busy || !app.whisperPanel.running)
                    Button("Restart") { app.restartWhisperServer() }
                        .disabled(busy || !app.whisperPanel.running)
                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Refresh") { app.refreshWhisperPanel() }
                }

                if let err = app.serverControlError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Model") {
                if app.whisperModels.isEmpty {
                    caption(app.whisperPanelReachable
                            ? "No models found in whisper.cpp's models folder."
                            : "Can't reach the control panel, so the model list is unavailable.")
                } else {
                    ForEach(app.whisperModels) { model in
                        modelRow(model)
                    }
                    caption("Switching hot-swaps a running server. Dictation keeps working, "
                            + "and the choice survives a restart.")
                }
            }

            Section("Control panel") {
                TextField("Panel URL", text: controlURLBinding)
                    .onSubmit { app.refreshWhisperPanel() }
                caption("The whisperctl supervisor that owns your own whisper-server process. "
                        + "VerbVox asks it to start, stop and swap models. The built-in engine "
                        + "in Recording doesn't need it.")
                Link("Open the panel in a browser", destination: panelLink)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .onAppear { app.refreshWhisperPanel() }
    }

    // MARK: Pieces

    private var busy: Bool { app.serverControlBusy || app.whisperModelSwitching }

    @ViewBuilder
    private var statusDot: some View {
        if !app.whisperPanelReachable {
            StatusDot(color: .red, text: "Control panel unreachable")
        } else if app.whisperPanel.healthy {
            StatusDot(color: .green, text: "Running")
        } else if app.whisperPanel.running {
            StatusDot(color: .orange, text: "Starting (loading model)")
        } else {
            StatusDot(color: .secondary, text: "Stopped")
        }
    }

    private var processDetail: String {
        let pid = app.whisperPanel.pid.map(String.init) ?? "—"
        return "pid \(pid) · up \(uptimeText)"
    }

    private var uptimeText: String {
        let total = app.whisperPanel.uptimeSec
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    private var panelLink: URL {
        URL(string: app.whisperControlURL) ?? URL(string: "http://127.0.0.1:8722")!
    }

    @ViewBuilder
    private func modelRow(_ model: WhisperServerControl.Model) -> some View {
        let selected = model.file == app.whisperPanel.model
        Button {
            app.setWhisperModel(model.file)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.name)
                    Text(model.isEnglishOnly ? "English only" : "All languages")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(sizeText(model.sizeMB))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func sizeText(_ mb: Int) -> String {
        mb >= 1024
            ? String(format: "%.2f GB", Double(mb) / 1024)
            : "\(mb) MB"
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
