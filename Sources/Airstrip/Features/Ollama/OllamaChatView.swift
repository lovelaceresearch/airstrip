import AppKit
import SwiftUI

/// Built-in AI Studio: local Ollama server management, external provider
/// keys, model switching, split-screen prompting, persona, and settings.
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
            ollama.refreshServerStatus()
            inputFocused = true
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            switch ollama.serverStatus {
            case .notInstalled:
                Button("Install Ollama") {
                    dependencyManager.installOllama()
                }
                .airstripGlassButton(prominent: true)
                .controlSize(.small)
                .noFocusRing()
            case .stopped:
                Button("Start Local Server") {
                    ollama.startServe()
                }
                .airstripGlassButton()
                .controlSize(.small)
                .noFocusRing()
            case .running:
                Button("Stop") {
                    ollama.stopServer()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .noFocusRing()
                .help("Stop the local Ollama server")
            case .starting, .unknown:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }

            if ollama.usableCloudProviderCount > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)

                Label(
                    "\(ollama.usableCloudProviderCount) cloud provider\(ollama.usableCloudProviderCount == 1 ? "" : "s")",
                    systemImage: "cloud"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
                .noFocusRing()
            }

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .noFocusRing()
            .help("API keys, persona, and generation settings")
            .sheet(isPresented: $showSettings) {
                AISettingsSheet()
            }
        }
    }

    private var statusText: String {
        switch ollama.serverStatus {
        case .running(let version):
            let count = ollama.models.count
            let models = count == 1 ? "1 local model" : "\(count) local models"
            return version.isEmpty ? models : "\(models) · Ollama v\(version)"
        case .starting:
            return "Starting local server..."
        case .unknown:
            return "Checking local server..."
        case .stopped:
            return "Local server off"
        case .notInstalled:
            return "Ollama not installed"
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

            Text("AI Studio")
                .font(.title3.weight(.semibold))

            Text(emptyStateHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if case .running = ollama.serverStatus, ollama.models.isEmpty {
                Button("Browse models on ollama.com") {
                    NSWorkspace.shared.open(URL(string: "https://ollama.com/library")!)
                }
                .airstripGlassButton()
                .noFocusRing()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var emptyStateHint: String {
        switch ollama.serverStatus {
        case .notInstalled:
            return "Use local Ollama models or add API keys for OpenAI, Gemini, Claude, and Mistral."
        case .running where ollama.models.isEmpty:
            return ollama.usableCloudProviderCount > 0
                ? "No local models downloaded yet, but cloud providers are available."
                : "No local models downloaded yet. Add an API key or pull a local model."
        default:
            return "Pick one model below, or press + to compare multiple local and cloud models side by side."
        }
    }

    private var singleColumn: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(ollama.turns) { turn in
                        UserBubble(text: turn.prompt)

                        if let targetID = ollama.selectedModels.first,
                           let response = turn.responses[targetID] ?? turn.responses.values.first {
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(ollama.selectedModels, id: \.self) { targetID in
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: ollama.target(for: targetID)?.provider.iconName ?? "sparkles")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)

                            Text(ollama.displayName(for: targetID))
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)

                            Spacer()

                            Button {
                                ollama.removeModel(targetID)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .noFocusRing()
                            .accessibilityLabel("Remove \(ollama.displayName(for: targetID)) from comparison")
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

                                        if let response = turn.responses[targetID] {
                                            ResponseBubble(response: response, showStats: ollama.settings.showStats)
                                        }
                                    }
                                }
                                .padding(12)

                                Color.clear.frame(height: 1).id("chat-bottom-\(targetID)")
                            }
                            .onChange(of: ollama.turns) { _ in
                                proxy.scrollTo("chat-bottom-\(targetID)", anchor: .bottom)
                            }
                        }
                    }
                    .frame(minWidth: 280, idealWidth: 340)

                    if targetID != ollama.selectedModels.last {
                        Divider()
                    }
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
                    .airstripGlassPanel(cornerRadius: 10, interactive: true, fallbackOpacity: 0.35)

                if ollama.isGenerating {
                    Button {
                        ollama.stopGenerating()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .noFocusRing()
                    .help("Stop generating")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .noFocusRing()
                    .help("Send")
                }
            }
        }
    }

    private var canSend: Bool {
        !ollama.selectedModels.isEmpty
            && ollama.selectedModels.allSatisfy(ollama.canUseTarget)
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend, !ollama.isGenerating else { return }
        ollama.send(draft)
        draft = ""
    }

    private var modelPickerRow: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Primary model picker.
                    if let primary = ollama.selectedModels.first {
                        Menu {
                            modelMenuItems { target in
                                ollama.setPrimaryModel(target.id)
                            } isChecked: { target in
                                target.id == primary
                            }

                            Divider()

                            Button("Refresh model list") {
                                Task { await ollama.refreshModels() }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: ollama.target(for: primary)?.provider.iconName ?? "cpu")
                                    .font(.system(size: 9))
                                    .foregroundStyle(ollama.target(for: primary)?.provider.brandColor ?? .secondary)

                                Text(ollama.displayName(for: primary))
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: 190, alignment: .leading)
                        }
                        .menuStyle(.borderlessButton)
                        .noFocusRing()
                    } else {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Add Model", systemImage: "plus.circle")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderless)
                        .noFocusRing()
                    }

                    // Additional models in this conversation.
                    ForEach(ollama.selectedModels.dropFirst(), id: \.self) { targetID in
                        let provider = ollama.target(for: targetID)?.provider

                        HStack(spacing: 4) {
                            Image(systemName: provider?.iconName ?? "cpu")
                                .font(.system(size: 8))
                                .foregroundStyle(provider?.brandColor ?? .secondary)

                            Text(ollama.displayName(for: targetID))
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .frame(maxWidth: 150, alignment: .leading)

                            Button {
                                ollama.removeModel(targetID)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .noFocusRing()
                            .accessibilityLabel("Remove \(ollama.displayName(for: targetID))")
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .airstripGlassCapsule(interactive: true)
                    }

                    // Add another model: same prompt goes to all, screen splits.
                    if !availableToAdd.isEmpty {
                        Menu {
                            ForEach(AIProvider.allCases) { provider in
                                let targets = availableToAdd.filter { $0.provider == provider }
                                if !targets.isEmpty {
                                    Section(provider == .ollama ? "Local (Ollama)" : provider.displayName) {
                                        ForEach(targets) { target in
                                            Button(targetMenuTitle(target)) {
                                                ollama.addModel(target.id)
                                            }
                                        }
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 12))
                        }
                        .menuStyle(.borderlessButton)
                        .noFocusRing()
                        .help("Send the same prompt to another model side by side")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ollama.selectedModels.count > 1 {
                Text("Split view: same prompt goes to \(ollama.selectedModels.count) models")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var availableToAdd: [AIChatTarget] {
        ollama.availableTargets.filter { !ollama.selectedModels.contains($0.id) }
    }

    /// Provider-sectioned model list shared by the primary picker menu.
    @ViewBuilder
    private func modelMenuItems(
        select: @escaping (AIChatTarget) -> Void,
        isChecked: @escaping (AIChatTarget) -> Bool
    ) -> some View {
        ForEach(AIProvider.allCases) { provider in
            let targets = ollama.availableTargets.filter { $0.provider == provider }
            if !targets.isEmpty {
                Section(provider == .ollama ? "Local (Ollama)" : provider.displayName) {
                    ForEach(targets) { target in
                        Button {
                            select(target)
                        } label: {
                            if isChecked(target) {
                                Label(targetMenuTitle(target), systemImage: "checkmark")
                            } else {
                                Text(targetMenuTitle(target))
                            }
                        }
                    }
                }
            }
        }
    }

    // Menu items live under provider sections, so the bare model name reads
    // better than the full "Provider · model" form.
    private func targetMenuTitle(_ target: AIChatTarget) -> String {
        if let sizeLabel = target.sizeLabel {
            return "\(target.name)  \(sizeLabel)"
        }
        return target.name
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
                .airstripGlassPanel(cornerRadius: 12, tint: .accentColor, fallbackOpacity: 0.75)
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
                    Text(formattedText)
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
            .airstripGlassPanel(cornerRadius: 12, fallbackOpacity: 0.35)
            .contextMenu {
                Button("Copy Response") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(response.text, forType: .string)
                }
            }

            Spacer(minLength: 40)
        }
    }

    /// Inline markdown (bold, italics, code) while keeping line breaks.
    private var formattedText: AttributedString {
        (try? AttributedString(
            markdown: response.text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        )) ?? AttributedString(response.text)
    }
}

// MARK: - Settings

/// Full settings sheet, sectioned like a native preferences window:
/// Providers (API keys), Persona, and Generation.
struct AISettingsSheet: View {
    @EnvironmentObject private var ollama: OllamaManager
    @Environment(\.dismiss) private var dismiss

    private enum Section: String, CaseIterable, Identifiable {
        case providers = "Providers"
        case persona = "Persona"
        case generation = "Generation"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .providers: return "key"
            case .persona: return "person.text.rectangle"
            case .generation: return "slider.horizontal.3"
            }
        }
    }

    @State private var section: Section = .providers

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat Settings")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .noFocusRing()
            }
            .padding(16)

            Picker("", selection: $section) {
                ForEach(Section.allCases) { section in
                    Label(section.rawValue, systemImage: section.icon).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                Group {
                    switch section {
                    case .providers:
                        providersSection
                    case .persona:
                        personaSection
                    case .generation:
                        generationSection
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, idealWidth: 540, maxWidth: 720, minHeight: 520, idealHeight: 580, maxHeight: 760)
    }

    // MARK: Providers

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local models come from Ollama automatically. Add API keys to also chat with cloud models — keys are stored in the macOS Keychain, never in files.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(AIProvider.cloudCases) { provider in
                ProviderSettingsRow(provider: provider)
            }
        }
    }

    // MARK: Persona

    private var personaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("The persona is a system prompt sent at the start of every conversation, to every model — local and cloud.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: Binding(
                get: { ollama.settings.systemPrompt },
                set: { ollama.settings.systemPrompt = $0 }
            ))
            .font(.system(size: 12.5))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(height: 180)
            .airstripGlassPanel(cornerRadius: 8, fallbackOpacity: 0.35)

            Text("Examples")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ForEach(Self.personaExamples, id: \.self) { example in
                Button {
                    ollama.settings.systemPrompt = example
                } label: {
                    Text(example)
                        .font(.system(size: 11))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .airstripGlassPanel(cornerRadius: 7, interactive: true, fallbackOpacity: 0.3)
                }
                .buttonStyle(.plain)
                .noFocusRing()
                .help("Use this persona")
            }
        }
    }

    private static let personaExamples = [
        "You are a concise assistant. Answer briefly, in Korean when the question is in Korean.",
        "You are a patient teacher. Explain step by step and assume no prior knowledge.",
        "You are a code reviewer. Point out bugs and risky patterns first, style second."
    ]

    // MARK: Generation

    private var generationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingSlider(
                "Temperature",
                value: Binding(get: { ollama.settings.temperature }, set: { ollama.settings.temperature = $0 }),
                range: 0...2,
                format: "%.2f",
                hint: "Higher = more creative, lower = more focused. Applies to all providers."
            )

            settingSlider(
                "Top P",
                value: Binding(get: { ollama.settings.topP }, set: { ollama.settings.topP = $0 }),
                range: 0...1,
                format: "%.2f",
                hint: "Nucleus sampling cutoff. Applies to all providers."
            )

            Divider()

            Text("Local models (Ollama) only")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            settingSlider(
                "Repeat penalty",
                value: Binding(get: { ollama.settings.repeatPenalty }, set: { ollama.settings.repeatPenalty = $0 }),
                range: 0.5...2,
                format: "%.2f",
                hint: "Discourages repeating the same phrases"
            )

            LabeledRow("Context window") {
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
                .frame(width: 220)
            }

            LabeledRow("Seed (0 = random)") {
                TextField("0", value: Binding(
                    get: { ollama.settings.seed },
                    set: { ollama.settings.seed = $0 }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
            }

            LabeledRow("Keep model loaded") {
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
                .frame(width: 260)
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
            .noFocusRing()
        }
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

private struct LabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 12))

            Spacer()

            content
        }
    }
}

private struct ProviderSettingsRow: View {
    @EnvironmentObject private var ollama: OllamaManager
    let provider: AIProvider

    private var config: CloudProviderConfig {
        ollama.providerSettings.config(for: provider)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: binding(\.isEnabled)) {
                    HStack(spacing: 6) {
                        Image(systemName: provider.iconName)
                            .font(.system(size: 12))
                            .foregroundStyle(provider.brandColor)

                        Text(provider.displayName)
                            .font(.system(size: 12.5, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()

                if let url = provider.keyConsoleURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Get API Key", systemImage: "arrow.up.right")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.borderless)
                    .noFocusRing()
                    .help("Open \(provider.displayName)'s API key page")
                }
            }

            if config.isEnabled {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        providerFields
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        providerFields
                    }
                }

                if !config.isUsable {
                    Label(
                        config.apiKey.isEmpty ? "Paste an API key to use \(provider.displayName)" : "Pick or type a model ID",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .airstripGlassPanel(cornerRadius: 10, fallbackOpacity: 0.35)
    }

    private var providerFields: some View {
        Group {
            SecureField("API key", text: binding(\.apiKey))
                .textFieldStyle(.roundedBorder)

            TextField("Model ID", text: binding(\.model))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, idealWidth: 170, maxWidth: 220)

            Menu {
                ForEach(provider.suggestedModels, id: \.self) { model in
                    Button(model) {
                        ollama.updateProvider(provider) { $0.model = model }
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .noFocusRing()
            .help("Suggested models")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<CloudProviderConfig, Value>) -> Binding<Value> {
        Binding(
            get: { ollama.providerSettings.config(for: provider)[keyPath: keyPath] },
            set: { value in
                ollama.updateProvider(provider) { config in
                    config[keyPath: keyPath] = value
                }
            }
        )
    }
}
