import SwiftUI

struct ProfanityView: View {
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var editing: ProfanityEntry?
    @State private var showAdd = false

    private var filtered: [ProfanityEntry] {
        guard !search.isEmpty else { return app.profanity }
        let q = search.lowercased()
        return app.profanity.filter {
            $0.word.lowercased().contains(q) || $0.replacement.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: app.bindingBool(ConfigCatalog.profanityEnabledKey, category: "features")) {
                    Text("Enable profanity filter").fontWeight(.medium)
                }
                Text("Replace these words in every app. Off leaves transcriptions untouched.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            List {
                ForEach(filtered) { entry in
                    ProfanityRow(entry: entry) { app.deleteProfanity(entry) }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = entry }
                        .contextMenu {
                            Button("Edit") { editing = entry }
                            Button("Delete", role: .destructive) { app.deleteProfanity(entry) }
                        }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Profanity")
        .searchable(text: $search, placement: .toolbar, prompt: "Search words")
        .toolbar {
            ToolbarItem { Button { showAdd = true } label: { Label("Add", systemImage: "plus") } }
        }
        .onAppear { app.loadProfanity() }
        .sheet(isPresented: $showAdd) {
            ProfanityEditor(entry: nil) { word, repl in app.addProfanity(word: word, replacement: repl) }
        }
        .sheet(item: $editing) { entry in
            ProfanityEditor(entry: entry, onSave: { word, repl in
                app.updateProfanity(ProfanityEntry(id: entry.id, word: word, replacement: repl))
            }, onDelete: { app.deleteProfanity(entry) })
        }
    }
}

private struct ProfanityRow: View {
    let entry: ProfanityEntry
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(entry.word).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
            Text(entry.replacement).fontWeight(.medium)
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .help("Delete")
            .opacity(hovering ? 1 : 0)          // reveal on hover, no layout shift
        }
        .onHover { hovering = $0 }
    }
}

struct ProfanityEditor: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ProfanityEntry?
    var onSave: (String, String) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var word = ""
    @State private var replacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry == nil ? "Add filter" : "Edit filter").font(.headline)
            Form {
                TextField("Word", text: $word)
                TextField("Replacement", text: $replacement)
            }
            .formStyle(.columns)
            Text("Leave “Replacement” empty to delete the word.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(word, replacement)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(word.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            word = entry?.word ?? ""
            replacement = entry?.replacement ?? ""
        }
    }
}
