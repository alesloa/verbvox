import SwiftUI

struct AIPromptsView: View {
    @EnvironmentObject var app: AppState
    @State private var selectedPrompt: String?
    @State private var draftText: String = ""
    @State private var showAddPrompt = false
    @State private var newName = ""

    /// Selected AI provider, defaulting to Groq (matches `ProviderFactory.ai()`).
    private var aiProvider: String {
        let v = app.str(ConfigCatalog.providerKey)
        return v.isEmpty ? "groq" : v
    }

    var body: some View {
        Form {
            Section("Provider") {
                Picker("AI provider", selection: app.bindingString(ConfigCatalog.providerKey, category: "ai_settings")) {
                    Text("Groq").tag("groq")
                    Text("Gemini").tag("gemini")
                    Text("OpenAI").tag("openai")
                }

                switch aiProvider {
                case "gemini":
                    SecureField("Gemini API key", text: app.bindingString(ConfigCatalog.geminiKeyKey, category: "api_keys"))
                    TextField("Gemini model", text: app.bindingString(ConfigCatalog.geminiModelKey, category: "ai_settings"))
                    caption("Default: gemini-2.5-flash")
                case "openai":
                    SecureField("OpenAI API key", text: app.bindingString(ConfigCatalog.openAIKeyKey, category: "api_keys"))
                    TextField("OpenAI model", text: app.bindingString(ConfigCatalog.openAIModelKey, category: "ai_settings"))
                    caption("Default: gpt-4o-mini")
                default: // groq
                    SecureField("Groq API key", text: app.bindingString(ConfigCatalog.groqKeyKey, category: "api_keys"))
                    TextField("Groq model", text: app.bindingString(ConfigCatalog.groqModelKey, category: "ai_settings"))
                    caption("Default: llama-3.3-70b-versatile")
                }

                caption("No AI key? Plain (no-AI) dictation still works — only With-AI features need a key.")
            }

            Section {
                HStack(alignment: .top, spacing: 12) {
                    promptList
                    promptEditor
                }
                .frame(minHeight: 240)
            } header: {
                HStack {
                    Text("Prompts")
                    Spacer()
                    Button { showAddPrompt = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI & Prompts")
        .onAppear { app.loadPrompts(); selectFirstIfNeeded() }
        .alert("New prompt", isPresented: $showAddPrompt) {
            TextField("Name (e.g. summarize)", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                app.savePrompt(name: name, text: "{text}")
                selectedPrompt = name
                draftText = "{text}"
                newName = ""
            }
            Button("Cancel", role: .cancel) { newName = "" }
        }
    }

    private var promptList: some View {
        List(selection: $selectedPrompt) {
            ForEach(app.prompts) { p in
                Text(p.name).tag(p.name)
            }
        }
        .frame(width: 170)
        .onChange(of: selectedPrompt) { _, new in
            draftText = app.prompts.first { $0.name == new }?.text ?? ""
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = selectedPrompt {
                Text(name).font(.headline)
                TextEditor(text: $draftText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                Text("Use {text} where the transcription should be inserted.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save") { app.savePrompt(name: name, text: draftText) }
                        .buttonStyle(.borderedProminent)
                    Button("Delete", role: .destructive) {
                        app.deletePrompt(name: name)
                        selectedPrompt = nil
                        selectFirstIfNeeded()
                    }
                    Spacer()
                }
            } else {
                Text("Select a prompt to edit.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectFirstIfNeeded() {
        if selectedPrompt == nil, let first = app.prompts.first {
            selectedPrompt = first.name
            draftText = first.text
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
