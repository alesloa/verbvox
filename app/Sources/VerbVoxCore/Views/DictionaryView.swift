import SwiftUI

struct DictionaryView: View {
    @EnvironmentObject var app: AppState
    @State private var search = ""
    @State private var editing: DictionaryEntry?
    @State private var showAdd = false

    private var filtered: [DictionaryEntry] {
        guard !search.isEmpty else { return app.dictionary }
        let q = search.lowercased()
        return app.dictionary.filter {
            $0.from.lowercased().contains(q) || $0.to.lowercased().contains(q)
                || $0.category.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(filtered) { entry in
                    DictionaryRow(entry: entry) { app.deleteDictionary(entry) }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = entry }
                        .contextMenu {
                            Button("Edit") { editing = entry }
                            Button("Delete", role: .destructive) { app.deleteDictionary(entry) }
                        }
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Dictionary")
        .searchable(text: $search, placement: .toolbar, prompt: "Search corrections")
        .toolbar {
            ToolbarItem {
                Button { showAdd = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .overlay(alignment: .bottom) {
            Text("\(app.dictionary.count) entries")
                .font(.caption).foregroundStyle(.secondary)
                .padding(6)
        }
        .onAppear { app.loadDictionary() }
        .sheet(isPresented: $showAdd) {
            DictionaryEditor(entry: nil) { cat, from, to in
                app.addDictionary(category: cat, from: from, to: to)
            }
        }
        .sheet(item: $editing) { entry in
            DictionaryEditor(entry: entry, onSave: { cat, from, to in
                app.updateDictionary(DictionaryEntry(id: entry.id, category: cat, from: from, to: to))
            }, onDelete: { app.deleteDictionary(entry) })
        }
    }
}

private struct DictionaryRow: View {
    let entry: DictionaryEntry
    var onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.from).foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(entry.to).fontWeight(.medium)
                }
                Text(entry.category).font(.caption).foregroundStyle(.tertiary)
            }
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
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
    }
}

struct DictionaryEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    let entry: DictionaryEntry?
    var onSave: (String, String, String) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var category = ""
    @State private var from = ""
    @State private var to = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry == nil ? "Add correction" : "Edit correction").font(.headline)
            Form {
                TextField("From (spoken)", text: $from)
                TextField("To (replacement)", text: $to)
                TextField("Category", text: $category)
            }
            .formStyle(.columns)
            Text("Leave “To” empty to delete the spoken word.")
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
                    onSave(category.isEmpty ? "Uncategorized" : category, from, to)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(from.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            category = entry?.category ?? ""
            from = entry?.from ?? ""
            to = entry?.to ?? ""
        }
    }
}
