import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var app: AppState

    // MARK: Selected providers (with the same defaults the ProviderFactory applies)

    /// Selected STT provider, defaulting to the whisper server (matches
    /// `ProviderFactory.stt()` treating an unset value as `whisper_server`).
    private var sttProvider: String {
        let v = app.str(ConfigCatalog.sttProviderKey)
        return v.isEmpty ? "whisper_server" : v
    }
    private var sttProviderBinding: Binding<String> {
        Binding(
            get: { sttProvider },
            set: {
                app.setStr(ConfigCatalog.sttProviderKey, $0, category: "stt")
                app.engine.refresh() // re-evaluate whisper reachability / N/A
            })
    }

    /// Selected TTS provider, defaulting to System (matches `ProviderFactory.tts()`).
    private var ttsProvider: String {
        let v = app.str(ConfigCatalog.ttsProviderKey)
        return v.isEmpty ? "system" : v
    }
    private var ttsProviderBinding: Binding<String> {
        Binding(
            get: { ttsProvider },
            set: { app.setStr(ConfigCatalog.ttsProviderKey, $0, category: "tts") })
    }

    // MARK: Whisper source (built-in engine or the user's own server)

    /// Built-in ⇄ Local ⇄ Remote. Switching re-syncs the effective URL and re-arms.
    private var sourceBinding: Binding<String> {
        Binding(
            get: { app.serverMode },
            set: { app.setServerMode($0) })
    }

    /// Built-in model id; "" is automatic.
    private var builtinModelBinding: Binding<String> {
        Binding(
            get: { app.str(ConfigCatalog.builtinModelKey) },
            set: { app.setStr(ConfigCatalog.builtinModelKey, $0, category: "whisper_builtin") })
    }

    private var localURLBinding: Binding<String> {
        Binding(
            get: { app.localServerURL },
            set: { app.setStr(ConfigCatalog.localURLKey, $0, category: "whisper_server") })
    }

    private var remoteURLBinding: Binding<String> {
        Binding(
            get: { app.remoteServerURL },
            set: { app.setStr(ConfigCatalog.remoteURLKey, $0, category: "whisper_server") })
    }

    /// Language for Apple's on-device transcriber. Empty means detect it.
    private var appleLocaleBinding: Binding<String> {
        Binding(
            get: { app.str(ConfigCatalog.sttAppleLocaleKey) },
            set: { app.setStr(ConfigCatalog.sttAppleLocaleKey, $0, category: "stt") })
    }

    // MARK: Other tunables

    private var minWordsBinding: Binding<Int> {
        Binding(
            get: { app.intVal(ConfigCatalog.minWordsForAIKey, default: 8) },
            set: { app.setInt(ConfigCatalog.minWordsForAIKey, $0, category: "features") })
    }

    private var ttsSpeedBinding: Binding<Double> {
        Binding(
            get: { Double(app.intVal(ConfigCatalog.ttsSpeedKey, default: 220)) },
            set: { app.setInt(ConfigCatalog.ttsSpeedKey, Int($0), category: "ai_response") })
    }

    var body: some View {
        Form {
            Section("Speech-to-text") {
                Picker("Provider", selection: sttProviderBinding) {
                    Text("Whisper server").tag("whisper_server")
                    Text("Apple (on-device)").tag("apple")
                    Text("Groq").tag("groq")
                    Text("OpenAI").tag("openai")
                    Text("Deepgram").tag("deepgram")
                }

                switch sttProvider {
                case "apple":
                    if app.appleSpeechAvailable {
                        Picker("Language", selection: appleLocaleBinding) {
                            Text("Detect automatically").tag("")
                            ForEach(app.appleSpeechLocales, id: \.self) { id in
                                Text(AppleSpeechSTT.localeDisplayName(id)).tag(id)
                            }
                        }
                        caption("Runs inside VerbVox on Apple's own model. No server, "
                                + "no API key, nothing leaves the Mac. The first use of a "
                                + "language downloads it.")
                        caption("Apple's model hears one language at a time. On "
                                + "\"Detect automatically\" VerbVox reads the first result and, "
                                + "if you were speaking another downloaded language, runs it "
                                + "again in that one. Pick a language to skip that check.")
                    } else {
                        caption("Needs macOS 26 or newer. This Mac can't run it.")
                    }
                case "groq":
                    TextField("Model", text: app.bindingString(ConfigCatalog.sttGroqModelKey, category: "stt"))
                    caption("Default: whisper-large-v3-turbo")
                    SecureField("Groq API key", text: app.bindingString(ConfigCatalog.groqKeyKey, category: "api_keys"))
                case "openai":
                    TextField("Model", text: app.bindingString(ConfigCatalog.sttOpenAIModelKey, category: "stt"))
                    caption("Default: whisper-1")
                    SecureField("OpenAI API key", text: app.bindingString(ConfigCatalog.openAIKeyKey, category: "api_keys"))
                case "deepgram":
                    TextField("Model", text: app.bindingString(ConfigCatalog.sttDeepgramModelKey, category: "stt"))
                    caption("Default: nova-3")
                    SecureField("Deepgram API key", text: app.bindingString(ConfigCatalog.deepgramKeyKey, category: "api_keys"))
                default: // whisper_server — the built-in engine or the user's own server
                    Picker("Source", selection: sourceBinding) {
                        Text("Built-in").tag("builtin")
                        Text("Local").tag("local")
                        Text("Remote (LAN)").tag("remote")
                    }
                    .pickerStyle(.segmented)

                    if app.serverMode == "builtin" {
                        BuiltinStatusView()
                        Picker("Speech model", selection: builtinModelBinding) {
                            Text("Automatic (recommended)").tag("")
                            ForEach(WhisperModelCatalog.models) { model in
                                Text(modelLabel(model)).tag(model.id)
                            }
                        }
                        caption("Automatic picks the most accurate model this Mac transcribes quickly and "
                                + "downloads it in the background. Other models download when you choose them.")
                        LabeledContent("Models folder") {
                            Button("Open folder") { app.openModelsFolder() }
                        }
                    } else {
                        if app.isRemoteMode {
                            TextField("Remote server URL", text: remoteURLBinding)
                                .onSubmit { app.applyServerSettingsAndRestart() }
                        } else {
                            TextField("Local server URL", text: localURLBinding)
                                .onSubmit { app.applyServerSettingsAndRestart() }
                        }

                        LabeledContent("Reachability") {
                            Text(serverReachable ? "● reachable" : "● unreachable")
                                .font(.caption)
                                .foregroundStyle(serverReachable ? Color.green : Color.orange)
                        }
                        Button(app.engine.busy ? "Re-checking…" : "Apply URL & re-check") {
                            app.applyServerSettingsAndRestart()
                        }
                        .disabled(app.engine.busy)

                        if app.builtinCovering {
                            caption("Your server isn't answering, so the built-in engine is handling "
                                    + "dictation until it's back.")
                            BuiltinStatusView()
                        } else {
                            caption("If your server stops answering for 15 seconds, the built-in engine "
                                    + "takes over until it's back.")
                        }
                        caption("Power and model live in the Whisper tab.")
                    }
                }

                if let err = app.engine.lastError {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Features") {
                ForEach(ConfigCatalog.features) { f in
                    Toggle(isOn: app.bindingBool(f.key, category: f.category)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.title)
                            Text(f.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("AI trigger") {
                Stepper(value: minWordsBinding, in: 1...50) {
                    LabeledContent("Min words for AI", value: "\(minWordsBinding.wrappedValue)")
                }
            }

            Section("Text-to-speech") {
                Picker("Provider", selection: ttsProviderBinding) {
                    Text("System").tag("system")
                    Text("OpenAI").tag("openai")
                    Text("Deepgram").tag("deepgram")
                }

                switch ttsProvider {
                case "openai":
                    TextField("Voice", text: app.bindingString(ConfigCatalog.ttsOpenAIVoiceKey, category: "tts"))
                    caption("Default: alloy")
                    SecureField("OpenAI API key", text: app.bindingString(ConfigCatalog.openAIKeyKey, category: "api_keys"))
                case "deepgram":
                    TextField("Model", text: app.bindingString(ConfigCatalog.ttsDeepgramModelKey, category: "tts"))
                    caption("Default: aura-2-thalia-en")
                    SecureField("Deepgram API key", text: app.bindingString(ConfigCatalog.deepgramKeyKey, category: "api_keys"))
                default: // system
                    TextField("Voice (optional)", text: app.bindingString(ConfigCatalog.ttsVoiceKey, category: "tts"))
                    caption("Leave blank for the system default voice.")
                }

                Picker("Response mode", selection: app.bindingString(ConfigCatalog.ttsModeKey, category: "ai_response")) {
                    Text("Speak").tag("speak")
                    Text("Replace").tag("replace")
                }
                VStack(alignment: .leading) {
                    LabeledContent("Speed (WPM)", value: "\(Int(ttsSpeedBinding.wrappedValue))")
                    Slider(value: ttsSpeedBinding, in: 90...500, step: 10)
                }
            }

            Section("Logging") {
                ForEach(ConfigCatalog.logging) { f in
                    Toggle(f.title, isOn: app.bindingBool(f.key, category: f.category))
                }
                Picker("Log format", selection: app.bindingString(ConfigCatalog.logFormatKey, category: "logging")) {
                    Text("Simple").tag("simple")
                    Text("Detailed").tag("detailed")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { app.loadAppleSpeechLocales() }
        .navigationTitle("Recording")
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    /// The user's own server answers. While the built-in engine covers for it, the
    /// engine's health check points at the built-in engine instead, so it is down.
    private var serverReachable: Bool { app.engine.serverRunning && !app.builtinCovering }

    private func modelLabel(_ model: WhisperModelInfo) -> String {
        "\(model.label) · \(model.size / 1_000_000) MB"
            + (app.builtin.status.downloadedModels.contains(model.id) ? " · downloaded" : "")
    }
}
