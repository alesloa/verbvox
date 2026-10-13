import SwiftUI

public enum SettingsTab: String, CaseIterable, Identifiable {
    case home, recording, whisper, ai, dictionary, profanity, hotkeys, history, logs, about
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .recording: return "Recording"
        case .whisper: return "Whisper"
        case .ai: return "AI & Prompts"
        case .dictionary: return "Dictionary"
        case .profanity: return "Profanity"
        case .hotkeys: return "Hotkeys"
        case .history: return "History"
        case .logs: return "Logs"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .recording: return "mic"
        case .whisper: return "waveform"
        case .ai: return "sparkles"
        case .dictionary: return "book.closed"
        case .profanity: return "exclamationmark.bubble"
        case .hotkeys: return "keyboard"
        case .history: return "clock.arrow.circlepath"
        case .logs: return "doc.text.magnifyingglass"
        case .about: return "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding<SettingsTab?>(
                get: { app.settingsSelection },
                set: { app.settingsSelection = $0 ?? .home }
            )) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 178, ideal: 196, max: 220)
            .navigationTitle("VerbVox")
        } detail: {
            Group {
                if !app.dbAvailable {
                    DatabaseMissingView()
                } else {
                    detail(for: app.settingsSelection)
                }
            }
            .frame(minWidth: 580, minHeight: 470)
        }
    }

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .recording: RecordingView()
        case .whisper: WhisperView()
        case .ai: AIPromptsView()
        case .dictionary: DictionaryView()
        case .profanity: ProfanityView()
        case .hotkeys: HotkeysView()
        case .history: HistoryView()
        case .logs: LogsView()
        case .about: AboutView()
        }
    }
}

struct DatabaseMissingView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Backend database not found").font(.title3.weight(.semibold))
            Text(app.loadError ?? app.paths.dbPath)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            Button("Choose backend folder…") { app.chooseBackendFolder() }
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
}
