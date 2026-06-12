import AppKit
import Foundation
import Security
import SwiftUI

// MARK: - Chat data model

enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case ollama
    case openAI
    case gemini
    case claude
    case mistral

    var id: String { rawValue }

    static let cloudCases: [AIProvider] = [.openAI, .gemini, .claude, .mistral]

    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        case .mistral: return "Mistral"
        }
    }

    var iconName: String {
        switch self {
        case .ollama: return "desktopcomputer"
        case .openAI: return "circle.hexagongrid"
        case .gemini: return "diamond"
        case .claude: return "text.bubble"
        case .mistral: return "wind"
        }
    }

    var defaultModel: String {
        switch self {
        case .ollama: return ""
        case .openAI: return "gpt-5.4-mini"
        case .gemini: return "gemini-2.5-flash"
        case .claude: return "claude-sonnet-4-6"
        case .mistral: return "mistral-small-latest"
        }
    }

    /// Curated picks shown in the model menu; any model ID can still be
    /// typed manually.
    var suggestedModels: [String] {
        switch self {
        case .ollama:
            return []
        case .openAI:
            return ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.4-nano"]
        case .gemini:
            return ["gemini-3.1-pro-preview", "gemini-3-flash-preview", "gemini-2.5-pro", "gemini-2.5-flash"]
        case .claude:
            return ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5"]
        case .mistral:
            return ["mistral-large-3", "mistral-small-latest", "codestral-latest"]
        }
    }

    /// Where to create or copy an API key.
    var keyConsoleURL: URL? {
        switch self {
        case .ollama: return nil
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .claude: return URL(string: "https://platform.claude.com/settings/keys")
        case .mistral: return URL(string: "https://console.mistral.ai/api-keys")
        }
    }

    var brandColor: Color {
        switch self {
        case .ollama: return .teal
        case .openAI: return Color(red: 0.07, green: 0.65, blue: 0.55)
        case .gemini: return .blue
        case .claude: return .orange
        case .mistral: return Color(red: 0.95, green: 0.45, blue: 0.1)
        }
    }
}

struct AIChatTarget: Identifiable, Hashable {
    let provider: AIProvider
    let name: String
    let sizeLabel: String?

    var id: String { "\(provider.rawValue):\(name)" }

    var displayName: String {
        provider == .ollama ? name : "\(provider.displayName) · \(name)"
    }
}

struct CloudProviderConfig: Codable, Equatable {
    var isEnabled: Bool
    var model: String
    var apiKey: String

    init(isEnabled: Bool = false, model: String, apiKey: String = "") {
        self.isEnabled = isEnabled
        self.model = model
        self.apiKey = apiKey
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        apiKey = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(model, forKey: .model)
    }

    var isUsable: Bool {
        isEnabled
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ExternalLLMSettings: Codable, Equatable {
    var openAI = CloudProviderConfig(model: AIProvider.openAI.defaultModel)
    var gemini = CloudProviderConfig(model: AIProvider.gemini.defaultModel)
    var claude = CloudProviderConfig(model: AIProvider.claude.defaultModel)
    var mistral = CloudProviderConfig(model: AIProvider.mistral.defaultModel)

    static let `default` = ExternalLLMSettings()

    func config(for provider: AIProvider) -> CloudProviderConfig {
        switch provider {
        case .ollama:
            return CloudProviderConfig(model: "")
        case .openAI:
            return openAI
        case .gemini:
            return gemini
        case .claude:
            return claude
        case .mistral:
            return mistral
        }
    }

    mutating func setConfig(_ config: CloudProviderConfig, for provider: AIProvider) {
        switch provider {
        case .ollama:
            return
        case .openAI:
            openAI = config
        case .gemini:
            gemini = config
        case .claude:
            claude = config
        case .mistral:
            mistral = config
        }
    }

    mutating func setAPIKey(_ key: String, for provider: AIProvider) {
        var config = self.config(for: provider)
        config.apiKey = key
        setConfig(config, for: provider)
    }
}

struct OllamaModel: Identifiable, Hashable, Decodable {
    let name: String
    let size: Int64?
    let modifiedAt: String?

    var id: String { name }

    var sizeLabel: String {
        guard let size else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    enum CodingKeys: String, CodingKey {
        case name
        case size
        case modifiedAt = "modified_at"
    }
}

/// One prompt and the responses from every model it was sent to.
struct ChatTurn: Identifiable, Equatable {
    let id = UUID()
    var prompt: String
    var sentAt = Date()
    /// Keyed by model name. Multiple entries mean a split-screen turn.
    var responses: [String: ModelResponse] = [:]
}

struct ModelResponse: Equatable {
    var text = ""
    var isStreaming = true
    var error: String?
    /// Filled from the final stream chunk; shown when "response stats" is on.
    var statsLine: String?
}

/// Generation settings and persona, persisted across launches.
/// Mirrors the documented Ollama modelfile/API options.
struct OllamaChatSettings: Codable, Equatable {
    var systemPrompt = ""
    var temperature = 0.8
    var topP = 0.9
    var topK = 40
    var numCtx = 4096
    var repeatPenalty = 1.1
    var seed = 0
    var keepAlive = "5m"
    var showStats = false

    static let `default` = OllamaChatSettings()
}

enum OllamaServerStatus: Equatable {
    case unknown
    case notInstalled
    case stopped
    case starting
    case running(String)

    var label: String {
        switch self {
        case .unknown: return "Checking..."
        case .notInstalled: return "Not installed"
        case .stopped: return "Stopped"
        case .starting: return "Starting..."
        case .running(let version): return version.isEmpty ? "Running" : "Running · v\(version)"
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

// MARK: - Manager

@MainActor
final class OllamaManager: ObservableObject {
    @Published var serverStatus: OllamaServerStatus = .unknown
    @Published var models: [OllamaModel] = []
    @Published var turns: [ChatTurn] = []
    @Published var selectedModels: [String] = []
    @Published var settings: OllamaChatSettings {
        didSet { saveSettings() }
    }
    @Published var providerSettings: ExternalLLMSettings {
        didSet {
            saveProviderSettings()
            normalizeSelectedTargets()
        }
    }

    var isGenerating: Bool {
        turns.last?.responses.values.contains { $0.isStreaming } == true
    }

    var availableTargets: [AIChatTarget] {
        let localTargets = models.map {
            AIChatTarget(provider: .ollama, name: $0.name, sizeLabel: $0.sizeLabel.isEmpty ? nil : $0.sizeLabel)
        }

        let cloudTargets = AIProvider.cloudCases.compactMap { provider -> AIChatTarget? in
            let config = providerSettings.config(for: provider)
            guard config.isUsable else { return nil }
            return AIChatTarget(
                provider: provider,
                name: config.model.trimmingCharacters(in: .whitespacesAndNewlines),
                sizeLabel: nil
            )
        }

        return localTargets + cloudTargets
    }

    var usableCloudProviderCount: Int {
        AIProvider.cloudCases.filter { providerSettings.config(for: $0).isUsable }.count
    }

    private var serveProcess: Process?
    private var generationTasks: [String: Task<Void, Never>] = [:]
    private static let baseURL = URL(string: "http://127.0.0.1:11434")!
    private static let settingsKey = "ollama.chat.settings"
    private static let providerSettingsKey = "ai.provider.settings"
    nonisolated private static let keychainService = "com.chanwoo.airstrip.llm-api-keys"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(OllamaChatSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }

        if let data = UserDefaults.standard.data(forKey: Self.providerSettingsKey),
           var saved = try? JSONDecoder().decode(ExternalLLMSettings.self, from: data) {
            for provider in AIProvider.cloudCases {
                saved.setAPIKey(Self.keychainAPIKey(for: provider) ?? "", for: provider)
            }
            providerSettings = saved
        } else {
            var defaults = ExternalLLMSettings.default
            for provider in AIProvider.cloudCases {
                defaults.setAPIKey(Self.keychainAPIKey(for: provider) ?? "", for: provider)
            }
            providerSettings = defaults
        }
        normalizeSelectedTargets()

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopSpawnedServer()
            }
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }

    private func saveProviderSettings() {
        if let data = try? JSONEncoder().encode(providerSettings) {
            UserDefaults.standard.set(data, forKey: Self.providerSettingsKey)
        }

        for provider in AIProvider.cloudCases {
            let key = providerSettings.config(for: provider).apiKey
            Self.setKeychainAPIKey(key, for: provider)
        }
    }

    func updateProvider(_ provider: AIProvider, mutate: (inout CloudProviderConfig) -> Void) {
        var settings = providerSettings
        var config = settings.config(for: provider)
        mutate(&config)
        settings.setConfig(config, for: provider)
        providerSettings = settings
    }

    // MARK: Server lifecycle

    /// Checks the local server and starts `ollama serve` if the binary is
    /// installed but nothing is listening.
    func ensureServer() {
        Task {
            if await checkServer() {
                await refreshModels()
                return
            }

            guard Self.findOllamaBinary() != nil else {
                serverStatus = .notInstalled
                return
            }

            startServe()
        }
    }

    func refreshServerStatus() {
        Task {
            if await checkServer() {
                await refreshModels()
            }
        }
    }

    func startServe() {
        guard serveProcess == nil else { return }
        serverStatus = .starting

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "exec ollama serve"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = ProjectStore.extendedPATH
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.serveProcess = nil
                if self?.serverStatus == .starting || self?.serverStatus.isRunning == true {
                    self?.serverStatus = .stopped
                }
            }
        }

        do {
            try process.run()
            serveProcess = process
            Task {
                // The server usually accepts connections within a second.
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(500))
                    if await checkServer() {
                        await refreshModels()
                        return
                    }
                }
                serverStatus = .stopped
            }
        } catch {
            serveProcess = nil
            serverStatus = .stopped
        }
    }

    func stopSpawnedServer() {
        guard let process = serveProcess else { return }
        process.terminate()
        serveProcess = nil
        serverStatus = .stopped
    }

    func stopServer() {
        if serveProcess != nil {
            stopSpawnedServer()
            return
        }

        guard serverStatus.isRunning else { return }
        serverStatus = .stopped

        Task {
            await Self.runShell("pkill -TERM -f 'ollama serve' >/dev/null 2>&1 || pkill -TERM -x ollama >/dev/null 2>&1 || true")
            try? await Task.sleep(for: .seconds(1))
            _ = await checkServer()
        }
    }

    /// True when Airstrip launched the server itself (so it may stop it).
    var ownsServer: Bool { serveProcess != nil }

    @discardableResult
    private func checkServer() async -> Bool {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = 1.5
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let version = (try? JSONDecoder().decode([String: String].self, from: data))?["version"] ?? ""
            serverStatus = .running(version)
            return true
        } catch {
            if serverStatus != .starting {
                serverStatus = Self.findOllamaBinary() == nil ? .notInstalled : .stopped
            }
            return false
        }
    }

    nonisolated static func findOllamaBinary() -> String? {
        let candidates = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: Models

    func refreshModels() async {
        struct TagsResponse: Decodable {
            let models: [OllamaModel]
        }

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(TagsResponse.self, from: data)
            models = response.models.sorted { $0.name < $1.name }
            normalizeSelectedTargets()
        } catch {
            models = []
            normalizeSelectedTargets()
        }
    }

    // MARK: Model selection

    func setPrimaryModel(_ id: String) {
        if let index = selectedModels.firstIndex(of: id) {
            selectedModels.remove(at: index)
            selectedModels.insert(id, at: 0)
        } else if selectedModels.isEmpty {
            selectedModels = [id]
        } else {
            selectedModels[0] = id
        }
    }

    func addModel(_ id: String) {
        guard !selectedModels.contains(id) else { return }
        selectedModels.append(id)
    }

    func removeModel(_ id: String) {
        guard selectedModels.count > 1 else { return }
        selectedModels.removeAll { $0 == id }
    }

    func target(for id: String) -> AIChatTarget? {
        availableTargets.first { $0.id == id } ?? Self.parseLegacyOllamaTarget(id)
    }

    func displayName(for id: String) -> String {
        target(for: id)?.displayName ?? id
    }

    func canUseTarget(_ id: String) -> Bool {
        guard let target = target(for: id) else { return false }
        switch target.provider {
        case .ollama:
            return serverStatus.isRunning
        case .openAI, .gemini, .claude, .mistral:
            return providerSettings.config(for: target.provider).isUsable
        }
    }

    private func normalizeSelectedTargets() {
        let available = Set(availableTargets.map(\.id))
        selectedModels = selectedModels.compactMap { id in
            if available.contains(id) {
                return id
            }
            let migrated = "ollama:\(id)"
            return available.contains(migrated) ? migrated : nil
        }

        if selectedModels.isEmpty, let first = availableTargets.first {
            selectedModels = [first.id]
        }
    }

    // MARK: Chat

    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !selectedModels.isEmpty,
              selectedModels.allSatisfy(canUseTarget),
              !isGenerating else { return }

        var turn = ChatTurn(prompt: trimmed)
        for targetID in selectedModels {
            turn.responses[targetID] = ModelResponse()
        }
        turns.append(turn)
        let turnID = turn.id

        for targetID in selectedModels {
            guard let target = target(for: targetID) else { continue }
            let history = chatHistory(for: targetID, excluding: turnID)
            generationTasks[targetID]?.cancel()
            generationTasks[targetID] = Task {
                switch target.provider {
                case .ollama:
                    await streamOllamaResponse(target: target, history: history, prompt: trimmed, turnID: turnID)
                case .openAI, .gemini, .claude, .mistral:
                    await requestCloudResponse(target: target, history: history, prompt: trimmed, turnID: turnID)
                }
            }
        }
    }

    func stopGenerating() {
        for (_, task) in generationTasks {
            task.cancel()
        }
        generationTasks = [:]
        guard let lastIndex = turns.indices.last else { return }
        for targetID in turns[lastIndex].responses.keys {
            turns[lastIndex].responses[targetID]?.isStreaming = false
        }
    }

    func clearConversation() {
        stopGenerating()
        turns = []
    }

    /// Builds the message history for one model. Turns answered by another
    /// model fall back to whichever response exists, so a newly added model
    /// still receives the conversation so far.
    private func chatHistory(for targetID: String, excluding turnID: UUID) -> [[String: String]] {
        var messages: [[String: String]] = []
        let persona = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persona.isEmpty {
            messages.append(["role": "system", "content": persona])
        }
        for turn in turns where turn.id != turnID {
            messages.append(["role": "user", "content": turn.prompt])
            let response = turn.responses[targetID] ?? turn.responses.values.first
            if let text = response?.text, !text.isEmpty {
                messages.append(["role": "assistant", "content": text])
            }
        }
        return messages
    }

    private func streamOllamaResponse(target: AIChatTarget, history: [[String: String]], prompt: String, turnID: UUID) async {
        var options: [String: Any] = [
            "temperature": settings.temperature,
            "top_p": settings.topP,
            "top_k": settings.topK,
            "num_ctx": settings.numCtx,
            "repeat_penalty": settings.repeatPenalty
        ]
        if settings.seed != 0 {
            options["seed"] = settings.seed
        }

        let payload: [String: Any] = [
            "model": target.name,
            "messages": history + [["role": "user", "content": prompt]],
            "stream": true,
            "keep_alive": settings.keepAlive,
            "options": options
        ]

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                var body = ""
                for try await line in bytes.lines {
                    body += line
                }
                let message = (try? JSONDecoder().decode([String: String].self, from: Data(body.utf8)))?["error"] ?? body
                finishResponse(turnID: turnID, targetID: target.id, error: message.isEmpty ? "Request failed (\(http.statusCode))" : message)
                return
            }

            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let data = line.data(using: .utf8),
                      let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                if let message = chunk["message"] as? [String: Any],
                   let content = message["content"] as? String, !content.isEmpty {
                    appendToken(turnID: turnID, targetID: target.id, token: content)
                }

                if chunk["done"] as? Bool == true {
                    finishResponse(turnID: turnID, targetID: target.id, stats: Self.statsLine(from: chunk))
                    return
                }
            }
            finishResponse(turnID: turnID, targetID: target.id)
        } catch is CancellationError {
            finishResponse(turnID: turnID, targetID: target.id)
        } catch {
            finishResponse(turnID: turnID, targetID: target.id, error: error.localizedDescription)
        }
    }

    /// Streams a response from a cloud provider over SSE so cloud models feel
    /// as live as local ones.
    private func requestCloudResponse(target: AIChatTarget, history: [[String: String]], prompt: String, turnID: UUID) async {
        do {
            switch target.provider {
            case .ollama:
                return
            case .openAI:
                try await streamOpenAICompatible(
                    endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
                    apiKey: providerSettings.openAI.apiKey,
                    target: target, history: history, prompt: prompt, turnID: turnID
                )
            case .mistral:
                try await streamOpenAICompatible(
                    endpoint: URL(string: "https://api.mistral.ai/v1/chat/completions")!,
                    apiKey: providerSettings.mistral.apiKey,
                    target: target, history: history, prompt: prompt, turnID: turnID
                )
            case .claude:
                try await streamClaude(target: target, history: history, prompt: prompt, turnID: turnID)
            case .gemini:
                try await streamGemini(target: target, history: history, prompt: prompt, turnID: turnID)
            }
        } catch is CancellationError {
            finishResponse(turnID: turnID, targetID: target.id)
        } catch {
            finishResponse(turnID: turnID, targetID: target.id, error: error.localizedDescription)
        }
    }

    private func streamOpenAICompatible(
        endpoint: URL,
        apiKey: String,
        target: AIChatTarget,
        history: [[String: String]],
        prompt: String,
        turnID: UUID
    ) async throws {
        let payload: [String: Any] = [
            "model": target.name,
            "messages": history + [["role": "user", "content": prompt]],
            "temperature": settings.temperature,
            "top_p": settings.topP,
            "stream": true,
            "stream_options": ["include_usage": true]
        ]

        let bytes = try await Self.openSSE(
            endpoint,
            headers: ["Authorization": "Bearer \(apiKey)"],
            payload: payload
        )

        var stats: String?
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard let chunk = Self.ssePayload(from: line) else { continue }
            if chunk.isDone { break }

            if let choices = chunk.json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                appendToken(turnID: turnID, targetID: target.id, token: content)
            }

            if let usage = chunk.json["usage"] as? [String: Any],
               let output = usage["completion_tokens"] as? Int {
                stats = "\(output) tokens"
            }
        }
        finishResponse(turnID: turnID, targetID: target.id, stats: stats)
    }

    private func streamClaude(target: AIChatTarget, history: [[String: String]], prompt: String, turnID: UUID) async throws {
        let persona = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = (history + [["role": "user", "content": prompt]])
            .filter { $0["role"] != "system" }
            .map { ["role": $0["role"] == "assistant" ? "assistant" : "user", "content": $0["content"] ?? ""] }

        var payload: [String: Any] = [
            "model": target.name,
            "max_tokens": 8192,
            "temperature": min(settings.temperature, 1),
            "messages": messages,
            "stream": true
        ]
        if !persona.isEmpty {
            payload["system"] = persona
        }

        let bytes = try await Self.openSSE(
            URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "x-api-key": providerSettings.claude.apiKey,
                "anthropic-version": "2023-06-01"
            ],
            payload: payload
        )

        var stats: String?
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard let chunk = Self.ssePayload(from: line) else { continue }
            let type = chunk.json["type"] as? String

            switch type {
            case "content_block_delta":
                if let delta = chunk.json["delta"] as? [String: Any],
                   let text = delta["text"] as? String, !text.isEmpty {
                    appendToken(turnID: turnID, targetID: target.id, token: text)
                }
            case "message_delta":
                if let usage = chunk.json["usage"] as? [String: Any],
                   let output = usage["output_tokens"] as? Int {
                    stats = "\(output) tokens"
                }
            case "error":
                let message = (chunk.json["error"] as? [String: Any])?["message"] as? String
                throw AIProviderError.requestFailed(message ?? "Claude returned an error.")
            case "message_stop":
                finishResponse(turnID: turnID, targetID: target.id, stats: stats)
                return
            default:
                break
            }
        }
        finishResponse(turnID: turnID, targetID: target.id, stats: stats)
    }

    private func streamGemini(target: AIChatTarget, history: [[String: String]], prompt: String, turnID: UUID) async throws {
        let encodedModel = target.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target.name
        guard let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):streamGenerateContent?alt=sse") else {
            throw AIProviderError.requestFailed("Invalid Gemini model name.")
        }

        let persona = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let contents = (history + [["role": "user", "content": prompt]])
            .filter { $0["role"] != "system" }
            .map { message -> [String: Any] in
                [
                    "role": message["role"] == "assistant" ? "model" : "user",
                    "parts": [["text": message["content"] ?? ""]]
                ]
            }

        var payload: [String: Any] = [
            "contents": contents,
            "generationConfig": [
                "temperature": min(settings.temperature, 2),
                "topP": settings.topP
            ]
        ]
        if !persona.isEmpty {
            payload["systemInstruction"] = ["parts": [["text": persona]]]
        }

        let bytes = try await Self.openSSE(
            endpoint,
            headers: ["x-goog-api-key": providerSettings.gemini.apiKey],
            payload: payload
        )

        var stats: String?
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard let chunk = Self.ssePayload(from: line) else { continue }

            if let candidates = chunk.json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty {
                    appendToken(turnID: turnID, targetID: target.id, token: text)
                }
            }

            if let usage = chunk.json["usageMetadata"] as? [String: Any],
               let output = usage["candidatesTokenCount"] as? Int {
                stats = "\(output) tokens"
            }
        }
        finishResponse(turnID: turnID, targetID: target.id, stats: stats)
    }

    private nonisolated static func statsLine(from chunk: [String: Any]) -> String? {
        guard let evalCount = chunk["eval_count"] as? Int,
              let evalDuration = chunk["eval_duration"] as? Int, evalDuration > 0 else {
            return nil
        }
        let tokensPerSecond = Double(evalCount) / (Double(evalDuration) / 1_000_000_000)
        var parts = [String(format: "%d tokens · %.1f tok/s", evalCount, tokensPerSecond)]
        if let total = chunk["total_duration"] as? Int {
            parts.append(String(format: "%.1fs total", Double(total) / 1_000_000_000))
        }
        return parts.joined(separator: " · ")
    }

    private func appendToken(turnID: UUID, targetID: String, token: String) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].responses[targetID]?.text += token
    }

    private func finishResponse(turnID: UUID, targetID: String, error: String? = nil, stats: String? = nil) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].responses[targetID]?.isStreaming = false
        if let error {
            turns[index].responses[targetID]?.error = error
        }
        if let stats {
            turns[index].responses[targetID]?.statsLine = stats
        }
        generationTasks[targetID] = nil
    }

    private nonisolated static func parseLegacyOllamaTarget(_ id: String) -> AIChatTarget? {
        if id.contains(":") { return nil }
        return AIChatTarget(provider: .ollama, name: id, sizeLabel: nil)
    }

    /// Opens a streaming POST request and validates the HTTP status before
    /// handing the byte stream back, surfacing the provider's own error
    /// message (wrong key, unknown model, quota) instead of a generic code.
    private nonisolated static func openSSE(
        _ url: URL,
        headers: [String: String],
        payload: [String: Any]
    ) async throws -> URLSession.AsyncBytes {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            var body = ""
            for try await line in bytes.lines where body.count < 4000 {
                body += line
            }
            let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
            throw AIProviderError.requestFailed(
                errorMessage(from: object) ?? "Request failed (\(http.statusCode))"
            )
        }
        return bytes
    }

    private struct SSEChunk {
        let json: [String: Any]
        let isDone: Bool
    }

    private nonisolated static func ssePayload(from line: String) -> SSEChunk? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" {
            return SSEChunk(json: [:], isDone: true)
        }
        guard let data = payload.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return SSEChunk(json: json, isDone: false)
    }

    private nonisolated static func errorMessage(from json: [String: Any]) -> String? {
        if let message = json["error"] as? String {
            return message
        }
        if let error = json["error"] as? [String: Any] {
            return (error["message"] as? String) ?? (error["type"] as? String)
        }
        return nil
    }

    private nonisolated static func runShell(_ command: String) async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }.value
    }

    private nonisolated static func keychainAPIKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func setKeychainAPIKey(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: provider.rawValue
        ]

        if trimmed.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}

enum AIProviderError: LocalizedError {
    case requestFailed(String)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return message
        case .unexpectedResponse:
            return "The provider returned an unexpected response."
        }
    }
}
