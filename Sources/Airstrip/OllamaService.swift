import AppKit
import Foundation

// MARK: - Chat data model

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

    var isGenerating: Bool {
        turns.last?.responses.values.contains { $0.isStreaming } == true
    }

    private var serveProcess: Process?
    private var generationTasks: [String: Task<Void, Never>] = [:]
    private static let baseURL = URL(string: "http://127.0.0.1:11434")!
    private static let settingsKey = "ollama.chat.settings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.settingsKey),
           let saved = try? JSONDecoder().decode(OllamaChatSettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }

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

    func startServe() {
        guard serveProcess == nil else { return }
        serverStatus = .starting

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "ollama serve"]
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
        let pid = process.processIdentifier
        if pid > 0 {
            kill(-pid, SIGTERM)
        } else {
            process.terminate()
        }
        serveProcess = nil
        serverStatus = .stopped
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
            if selectedModels.isEmpty, let first = models.first {
                selectedModels = [first.name]
            }
            selectedModels.removeAll { name in !models.contains(where: { $0.name == name }) }
        } catch {
            models = []
        }
    }

    // MARK: Model selection

    func setPrimaryModel(_ name: String) {
        if let index = selectedModels.firstIndex(of: name) {
            selectedModels.remove(at: index)
            selectedModels.insert(name, at: 0)
        } else if selectedModels.isEmpty {
            selectedModels = [name]
        } else {
            selectedModels[0] = name
        }
    }

    func addModel(_ name: String) {
        guard !selectedModels.contains(name) else { return }
        selectedModels.append(name)
    }

    func removeModel(_ name: String) {
        guard selectedModels.count > 1 else { return }
        selectedModels.removeAll { $0 == name }
    }

    // MARK: Chat

    func send(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !selectedModels.isEmpty, !isGenerating else { return }

        var turn = ChatTurn(prompt: trimmed)
        for model in selectedModels {
            turn.responses[model] = ModelResponse()
        }
        turns.append(turn)
        let turnID = turn.id

        for model in selectedModels {
            let history = chatHistory(for: model, excluding: turnID)
            generationTasks[model]?.cancel()
            generationTasks[model] = Task {
                await streamResponse(model: model, history: history, prompt: trimmed, turnID: turnID)
            }
        }
    }

    func stopGenerating() {
        for (_, task) in generationTasks {
            task.cancel()
        }
        generationTasks = [:]
        guard let lastIndex = turns.indices.last else { return }
        for model in turns[lastIndex].responses.keys {
            turns[lastIndex].responses[model]?.isStreaming = false
        }
    }

    func clearConversation() {
        stopGenerating()
        turns = []
    }

    /// Builds the message history for one model. Turns answered by another
    /// model fall back to whichever response exists, so a newly added model
    /// still receives the conversation so far.
    private func chatHistory(for model: String, excluding turnID: UUID) -> [[String: String]] {
        var messages: [[String: String]] = []
        let persona = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !persona.isEmpty {
            messages.append(["role": "system", "content": persona])
        }
        for turn in turns where turn.id != turnID {
            messages.append(["role": "user", "content": turn.prompt])
            let response = turn.responses[model] ?? turn.responses.values.first
            if let text = response?.text, !text.isEmpty {
                messages.append(["role": "assistant", "content": text])
            }
        }
        return messages
    }

    private func streamResponse(model: String, history: [[String: String]], prompt: String, turnID: UUID) async {
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
            "model": model,
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
                finishResponse(turnID: turnID, model: model, error: message.isEmpty ? "Request failed (\(http.statusCode))" : message)
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
                    appendToken(turnID: turnID, model: model, token: content)
                }

                if chunk["done"] as? Bool == true {
                    finishResponse(turnID: turnID, model: model, stats: Self.statsLine(from: chunk))
                    return
                }
            }
            finishResponse(turnID: turnID, model: model)
        } catch is CancellationError {
            finishResponse(turnID: turnID, model: model)
        } catch {
            finishResponse(turnID: turnID, model: model, error: error.localizedDescription)
        }
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

    private func appendToken(turnID: UUID, model: String, token: String) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].responses[model]?.text += token
    }

    private func finishResponse(turnID: UUID, model: String, error: String? = nil, stats: String? = nil) {
        guard let index = turns.firstIndex(where: { $0.id == turnID }) else { return }
        turns[index].responses[model]?.isStreaming = false
        if let error {
            turns[index].responses[model]?.error = error
        }
        if let stats {
            turns[index].responses[model]?.statsLine = stats
        }
        generationTasks[model] = nil
    }
}
