import SwiftUI

struct HotkeysView: View {
    @EnvironmentObject var app: AppState
    @State private var noAI = HotkeyCombo([])
    @State private var withAI = HotkeyCombo([])
    @State private var changed = false

    var body: some View {
        Form {
            Section("Hold-to-talk hotkeys") {
                HotkeyRecorderView(title: "No-AI recording", combo: $noAI) {
                    app.setNoAIHotkey($0); changed = true
                }
                HotkeyRecorderView(title: "With-AI recording", combo: $withAI) {
                    app.setWithAIHotkey($0); changed = true
                }
            }

            Section {
                Label("Hold the chosen modifiers to record, release to stop. ESC stops playback.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
                if noAI.modifiers.count < 2 || withAI.modifiers.count < 2 {
                    Label("Single-modifier hotkeys can clash with shortcuts like ⌘C. Two or more is safer.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange)
                }
            }

            if changed {
                Section {
                    HStack {
                        Text("Restart the engine to apply new hotkeys.")
                        Spacer()
                        Button("Restart engine") {
                            app.restartEngine()
                            changed = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Hotkeys")
        .onAppear {
            noAI = app.noAIHotkey
            withAI = app.withAIHotkey
        }
    }
}
