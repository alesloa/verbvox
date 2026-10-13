import SwiftUI
import AppKit

struct LogsView: View {
    @EnvironmentObject var app: AppState
    @State private var which: LogChoice = .engine

    enum LogChoice: String, CaseIterable, Identifiable {
        case engine = "Engine"
        case server = "Whisper Server"
        var id: String { rawValue }
    }

    private var path: String {
        which == .engine ? app.engine.engineLogPath : app.engine.serverLogPath
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $which) {
                    ForEach(LogChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .labelsHidden()

                Spacer()

                if app.engine.sttIsWhisperServer {
                    StatusDot(color: app.engine.serverRunning ? .green : .secondary, text: "Server")
                } else {
                    StatusDot(color: .secondary, text: "Cloud STT")
                }
                StatusDot(color: app.engine.engineRunning ? .green : .secondary, text: "Engine")

                Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Open in Console")
                Button { FileManager.default.createFile(atPath: path, contents: Data()) } label: {
                    Image(systemName: "trash")
                }
                .help("Clear this log")
            }

            // Re-reads the file every second for a live tail.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let contents = LogReader.tail(of: path, maxBytes: 80_000)
                ScrollView {
                    Text(contents.isEmpty ? "— no output yet —" : contents)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .defaultScrollAnchor(.bottom)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8))
            }

            Text(path).font(.caption2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .navigationTitle("Logs")
        .onAppear { app.engine.refresh() }
    }
}
