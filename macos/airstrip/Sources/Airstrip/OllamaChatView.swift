import AppKit
import SwiftUI

/// Built-in Ollama chat tab: server management, model switching,
/// multi-model split-screen prompting, persona, and generation settings.
struct OllamaChatView: View {
    @EnvironmentObject private var ollama: OllamaManager
    @EnvironmentObject private var dependencyManager: DependencyManager

    @State private var draft = ""
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

            Divider()

            content

            Divider()

            inputBar
                .padding(12)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            ollama.ensureServer()
            inputFocused = true
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text("Ollama · \(ollama.serverStatus.label)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            switch ollama.serverStatus {
            case .notInstalled:
                Button("Install Ollama") {
                    dependencyManager.installOllama()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            case .stopped:
                Button("Start Server") {
                    ollama.startServe()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .running:
                if ollama.ownsServer {
                    Button("Stop Server") {
                        ollama.stopSpawnedServer()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
            case .starting, .unknown:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }

            Spacer()

            if !ollama.turns.isEmpty {
                Button {
                    ollama.clearConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Persona and generation settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                OllamaSettingsPopover()
            }
        }
    }

    private var statusColor: Color {
        switch ollama.serverStatus {
        case .running: return .green
        case .starting, .unknown: return .yellow
        case .stopped, .notInstalled: return .orange
        }
    }

    // MARK: Conversation area

    @ViewBuilder
    private var content: some View {
        if ollama.turns.isEmpty {
            emptyState
        } else if ollama.selectedModels.count > 1 {
            splitColumns
        } else {
            singleColumn
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .top, endPoint: .bottom))

            Text("Chat with local models")
                .font(.title3.weight(.semibold))

            Text(emptyStateHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if case .running = ollama.serverStatus, ollama.models.isEmpty {
                Button("Browse models on ollama.com") {
                    NSWorkspace.shared.open(URL(string: "https://ollama.com/library")!)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var emptyStateHint: String {
        switch ollama.serverStatus {
        case .notInstalled:
            return "Install Ollama to run AI models privately on this Mac."
        case .running where ollama.models.isEmpty:
            return "No models downloaded yet. Pull one in Terminal, e.g.:\nollama pull llama3.2"
        default:
            return "Everything stays on this Mac. Pick a model below, press + to race several models against the same prompt."
        }
    }

    private var singleColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(ollama.turns) { turn in
                        UserBubble(text: turn.prompt)

                        if let model = ollama.selectedModels.first,
                           let response = turn.responses[model] ?? turn.responses.values.first {
                            ResponseBubble(response: response, showStats: ollama.settings.showStats)
                        }
                    }
                }
                .padding(16)

                Color.clear.frame(height: 1).id("chat-bottom")
            }
            .onChange(of: ollama.turns) { _ in
                proxy.scrollTo("chat-bottom", anchor: .bottom)
            }
        }
    }

    private var splitColumns: some View {
        HStack(spacing: 0) {
            ForEach(ollama.selectedModels, id: \.self) { model in
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text(model)
                            .font(.system(size: 11.5, weight: .semibold))
                            .lineLimit(1)

                        Spacer()

                        Button {
                            ollama.removeModel(model)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove this model from the conversation")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.4))

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 14) {
                                ForEach(ollama.turns) { turn in
                                    UserBubble(text: turn.prompt)

                                    if let response = turn.responses[model] {
                                        ResponseBubble(response: response, showStats: ollama.settings.showStats)
                                    }
                                }
                            }
                            .padding(12)

                            Color.clear.frame(height: 1).id("chat-bottom-\(model)")
                        }
                        .onChange(of: ollama.turns) { _ in
                            proxy.scrollTo("chat-bottom-\(model)", anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if model != ollama.selectedModels.last {
                    Divider()
                }
            }
        }
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            modelPickerRow

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message...", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .font(.system(size: 13))
                    .focused($inputFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                if ollama.isGenerating {
                    Button {
                        ollama.stopGenerating()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Stop generating")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .help("Send")
                }
            }
        }
    }

    private var canSend: Bool {
        ollama.serverStatus.isRunning
            && !ollama.selectedModels.isEmpty
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend, !ollama.isGenerating else { return }
        ollama.send(draft)
        draft = ""
    }

    private var modelPickerRow: some View {
        HStack(spacing: 6) {
            // Primary model picker.
            if let primary = ollama.selectedModels.first {
                Menu {
                    ForEach(ollama.models) { model in
                        Button {
                            ollama.setPrimaryModel(model.name)
                        } label: {
                            if model.name == primary {
                                Label("\(model.name)  \(model.sizeLabel)", systemImage: "checkmark")
                            } else {
                                Text("\(model.name)  \(model.sizeLabel)")
                            }
                        }
                    }

                    Divider()

                    Button("Refresh model list") {
                        Task { await ollama.refreshModels() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 9))

                        Text(primary)
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Additional models in this conversation.
            ForEach(ollama.selectedModels.dropFirst(), id: \.self) { model in
                HStack(spacing: 4) {
                    Text(model)
                        .font(.system(size: 11))

                    Button {
                        ollama.removeModel(model)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }

            // Add another model: same prompt goes to all, screen splits.
            if !availableToAdd.isEmpty {
                Menu {
                    ForEach(availableToAdd) { model in
                        Button(model.name) {
                            ollama.addModel(model.name)
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Send the same prompt to another model side by side")
            }

            Spacer()

            if ollama.selectedModels.count > 1 {
                Text("Split view: same prompt goes to \(ollama.selectedModels.count) models")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var availableToAdd: [OllamaModel] {
        ollama.models.filter { !ollama.selectedModels.contains($0.name) }
    }
}

// MARK: - Bubbles

private struct UserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)

            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
        }
    }
}

private struct ResponseBubble: View {
    let response: ModelResponse
    let showStats: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                if let error = response.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                } else if response.text.isEmpty, response.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.6)

                        Text("Thinking...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(response.text)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                }

                if showStats, let stats = response.statsLine {
                    Text(stats)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            Spacer(minLength: 40)
        }
    }
}

// MARK: - Settings

private struct OllamaSettingsPopover: View {
    @EnvironmentObject private var ollama: OllamaManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Persona")
                    .font(.headline)

                Text("System prompt sent before every conversation. Example: \"You are a concise assistant. Always answer in Korean.\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: Binding(
                    get: { ollama.settings.systemPrompt },
                    set: { ollama.settings.systemPrompt = $0 }
                ))
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 90)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                Divider()

                Text("Generation")
                    .font(.headline)

                settingSlider(
                    "Temperature",
                    value: Binding(get: { ollama.settings.temperature }, set: { ollama.settings.temperature = $0 }),
                    range: 0...2,
                    format: "%.2f",
                    hint: "Higher = more creative, lower = more focused"
                )

                settingSlider(
                    "Top P",
                    value: Binding(get: { ollama.settings.topP }, set: { ollama.settings.topP = $0 }),
                    range: 0...1,
                    format: "%.2f",
                    hint: "Nucleus sampling cutoff"
                )

                settingSlider(
                    "Repeat penalty",
                    value: Binding(get: { ollama.settings.repeatPenalty }, set: { ollama.settings.repeatPenalty = $0 }),
                    range: 0.5...2,
                    format: "%.2f",
                    hint: "Discourages repeating the same phrases"
                )

                HStack {
                    Text("Context window")
                        .font(.system(size: 12))

                    Spacer()

                    Picker("", selection: Binding(
                        get: { ollama.settings.numCtx },
                        set: { ollama.settings.numCtx = $0 }
                    )) {
                        Text("2k").tag(2048)
                        Text("4k").tag(4096)
                        Text("8k").tag(8192)
                        Text("16k").tag(16384)
                        Text("32k").tag(32768)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                HStack {
                    Text("Seed (0 = random)")
                        .font(.system(size: 12))

                    Spacer()

                    TextField("0", value: Binding(
                        get: { ollama.settings.seed },
                        set: { ollama.settings.seed = $0 }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                }

                HStack {
                    Text("Keep model loaded")
                        .font(.system(size: 12))

                    Spacer()

                    Picker("", selection: Binding(
                        get: { ollama.settings.keepAlive },
                        set: { ollama.settings.keepAlive = $0 }
                    )) {
                        Text("5 min").tag("5m")
                        Text("30 min").tag("30m")
                        Text("Forever").tag("-1")
                        Text("Unload now").tag("0")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                Toggle(isOn: Binding(
                    get: { ollama.settings.showStats },
                    set: { ollama.settings.showStats = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show response stats")
                            .font(.system(size: 12))

                        Text("Token count and speed under each answer (like ollama --verbose)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/ollama/ollama/blob/main/docs/modelfile.md#valid-parameters-and-values")!)
                } label: {
                    Label("Ollama parameter documentation", systemImage: "book")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
            .padding(16)
        }
        .frame(width: 360, height: 480)
    }

    private func settingSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.system(size: 12))

                Spacer()

                Text(String(format: format, value.wrappedValue))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)

            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }
}
