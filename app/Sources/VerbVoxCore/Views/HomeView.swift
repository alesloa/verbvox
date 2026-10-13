import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var app: AppState

    /// The bar the pointer is over in the Activity chart ("YYYY-MM-DD"), or nil.
    @State private var selectedDay: String?

    private var recentDays: [DayCount] { Array(app.dailyCounts.suffix(30)) }

    private var selectedDayCount: DayCount? {
        guard let selectedDay else { return nil }
        return recentDays.first { $0.day == selectedDay }
    }

    private var timeSaved: String {
        // Words typed by voice vs ~40 wpm typing baseline.
        let minutesTyping = Double(app.summary.totalWords) / 40.0
        let hours = minutesTyping / 60.0
        if hours >= 1 { return String(format: "%.1f h", hours) }
        return String(format: "%.0f min", minutesTyping)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                speechNotice
                engineControls

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    StatCard(title: "Words", value: app.summary.totalWords.formatted(),
                             systemImage: "text.word.spacing")
                    StatCard(title: "Avg WPM", value: String(format: "%.0f", app.summary.avgWPM),
                             systemImage: "speedometer", accent: .green)
                    StatCard(title: "Sessions", value: app.summary.totalCount.formatted(),
                             systemImage: "waveform", accent: .purple)
                    StatCard(title: "Time saved", value: timeSaved,
                             systemImage: "clock", accent: .orange)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity").font(.headline)
                        Spacer()
                        if let sel = selectedDayCount {
                            Text("\(formattedDay(sel.day))  ·  \(sel.words.formatted()) words  ·  \(sel.count) \(sel.count == 1 ? "session" : "sessions")")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Last 30 days · hover a bar for details")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    if app.dailyCounts.isEmpty {
                        emptyChart
                    } else {
                        activityChart
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent").font(.headline)
                        Spacer()
                        Button { app.loadStats() } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless)
                    }
                    if app.recentLogs.isEmpty {
                        Text("No transcriptions logged yet.")
                            .foregroundStyle(.secondary).font(.callout).padding(.vertical, 8)
                    } else {
                        ForEach(app.recentLogs.prefix(8)) { entry in
                            RecentRow(entry: entry)
                        }
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Home")
        .onAppear { app.loadStats() }
    }

    /// Activity bar chart with pointer selection: hovering a bar highlights it,
    /// drops a rule + tooltip (date, words, sessions), and dims the others.
    private var activityChart: some View {
        Chart {
            ForEach(recentDays) { day in
                BarMark(
                    x: .value("Day", day.day),
                    y: .value("Words", day.words))
                .foregroundStyle(Color.accentColor.gradient)
            }
            if let sel = selectedDayCount {
                RuleMark(x: .value("Day", sel.day))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .annotation(position: .top,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        dayTooltip(sel)
                    }
            }
        }
        .chartXAxis(.hidden)
        .chartXSelection(value: $selectedDay)
        .frame(height: 180)
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func dayTooltip(_ d: DayCount) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedDay(d.day)).font(.caption).bold()
            Text("\(d.words.formatted()) words").font(.caption2).foregroundStyle(.secondary)
            Text("\(d.count) \(d.count == 1 ? "session" : "sessions")")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .shadow(radius: 2)
    }

    /// "2026-07-01" → "Wed, Jul 1".
    private func formattedDay(_ s: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: s) else { return s }
        let out = DateFormatter()
        out.dateFormat = "EEE, MMM d"
        return out.string(from: date)
    }

    private var engineControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Text("Engine").font(.headline)
                Spacer()
                if app.engine.sttIsWhisperServer {
                    StatusDot(color: app.engine.serverRunning ? .green : .secondary,
                              text: app.speechOnBuiltin ? builtinDotLabel : "Server")
                } else {
                    StatusDot(color: .secondary, text: "Cloud STT")
                }
                StatusDot(color: app.engine.engineRunning ? .green : .secondary, text: "Engine")
            }
            HStack {
                if app.engine.engineRunning {
                    Button("Stop") { app.stopEngine() }
                    Button("Restart") { app.restartEngine() }
                } else {
                    Button(app.engine.busy ? "Starting…" : "Start Engine") { app.startEngine() }
                        .disabled(app.engine.busy)
                        .buttonStyle(.borderedProminent)
                }
                Spacer()
                Toggle("Start when app opens", isOn: Binding(
                    get: { app.shouldAutostart },
                    set: { app.setBool(ConfigCatalog.autostartKey, $0, category: "engine") }))
                    .toggleStyle(.switch)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private var builtinDotLabel: String {
        switch app.builtin.status.phase {
        case .downloading: return "Downloading"
        case .starting, .warmingUp: return "Starting"
        case .failed: return "Speech stopped"
        default: return "Speech"
        }
    }

    /// Built-in engine progress until it is ready, and what happens while the
    /// user's own server is down.
    @ViewBuilder
    private var speechNotice: some View {
        if app.speechOnBuiltin, app.builtin.status.phase != .ready {
            noticeBox { BuiltinStatusView() }
        }
        let externalDown = WhisperSource.usesExternal(app.config) && !app.builtinCovering
            && app.engine.engineRunning && !app.engine.serverRunning
        if app.builtinCovering || externalDown {
            noticeBox {
                VStack(alignment: .leading, spacing: 3) {
                    Text("The whisper server at \(app.str(ConfigCatalog.serverURLKey)) is not responding.")
                        .font(.headline)
                    Text(app.builtinCovering
                         ? "The built-in speech engine is handling dictation until the server is back."
                         : "If it stays down, the built-in speech engine takes over in a few seconds.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func noticeBox<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private var emptyChart: some View {
        Text("No activity data")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct RecentRow: View {
    let entry: LogEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.text).lineLimit(2).font(.callout)
            HStack(spacing: 6) {
                Text(entry.app).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(entry.timestamp).foregroundStyle(.tertiary)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}
