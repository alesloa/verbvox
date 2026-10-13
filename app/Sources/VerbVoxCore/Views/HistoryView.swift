import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var app: AppState
    @State private var search = ""

    private var filtered: [LogEntry] {
        guard !search.isEmpty else { return app.recentLogs }
        let q = search.lowercased()
        return app.recentLogs.filter {
            $0.text.lowercased().contains(q) || $0.app.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                summaryChip("Sessions", app.summary.totalCount.formatted())
                summaryChip("Words", app.summary.totalWords.formatted())
                summaryChip("Avg WPM", String(format: "%.0f", app.summary.avgWPM))
                summaryChip("Best WPM", String(format: "%.0f", app.summary.maxWPM))
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            List {
                ForEach(filtered) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.text).font(.callout)
                        HStack(spacing: 6) {
                            Text(entry.app).foregroundStyle(.secondary)
                            Text("·").foregroundStyle(.tertiary)
                            Text(entry.timestamp).foregroundStyle(.tertiary)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                    .textSelection(.enabled)
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("History")
        .searchable(text: $search, placement: .toolbar, prompt: "Search history")
        .toolbar {
            ToolbarItem { Button { app.loadStats() } label: { Label("Refresh", systemImage: "arrow.clockwise") } }
        }
        .onAppear { app.loadStats() }
    }

    private func summaryChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }
}
