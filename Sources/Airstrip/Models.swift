import Foundation

struct AirstripProject: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var path: URL
    var createdAt: Date
    var manifest: ProjectManifest
    var notes: String?

    init(id: UUID = UUID(), name: String, path: URL, createdAt: Date = Date(), manifest: ProjectManifest, notes: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
        self.manifest = manifest
        self.notes = notes
    }
}

struct ProjectManifest: Codable, Equatable {
    var name: String?
    var icon: String?
    var run: String?
    var actions: [ProjectAction]?
    var requirements: String?
    var tools: [ProjectTool]?
    var ollama: OllamaManifest?

    static let empty = ProjectManifest(
        name: nil,
        icon: nil,
        run: nil,
        actions: nil,
        requirements: nil,
        tools: nil,
        ollama: nil
    )
}

struct ProjectAction: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var command: String
    var isDefault: Bool
    var web: WebServerConfig?

    init(id: UUID = UUID(), name: String, command: String, isDefault: Bool = false, web: WebServerConfig? = nil) {
        self.id = id
        self.name = name
        self.command = command
        self.isDefault = isDefault
        self.web = web
    }

    // Hand-written manifests omit `id` and usually `isDefault`, so synthesized
    // decoding would reject every real airstrip.json that uses actions.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        web = try container.decodeIfPresent(WebServerConfig.self, forKey: .web)
    }
}

/// A command-line tool a project needs at runtime, with an optional Homebrew
/// package that provides it (e.g. command "pdftoppm", brew "poppler").
struct ProjectTool: Codable, Equatable, Identifiable {
    var command: String
    var brew: String?

    var id: String { command }
}

struct WebServerConfig: Codable, Equatable {
    var port: Int
    var openPath: String?
    var openOnStart: Bool?
    var allowPortFallback: Bool?

    init(port: Int, openPath: String? = nil, openOnStart: Bool? = nil, allowPortFallback: Bool? = nil) {
        self.port = port
        self.openPath = openPath
        self.openOnStart = openOnStart
        self.allowPortFallback = allowPortFallback
    }
}

struct OllamaManifest: Codable, Equatable {
    var models: [String]
}

/// One run of a project action, with its full terminal output.
struct RunRecord: Identifiable, Equatable {
    var id = UUID()
    var actionName: String
    var startedAt: Date
    var endedAt: Date?
    var output = ""
    var exitCode: Int32?

    var isOpen: Bool { exitCode == nil && endedAt == nil }
}

struct ProjectRuntimeState: Equatable {
    var isRunning = false
    var isPreparing = false
    var runs: [RunRecord] = []
    var lastExitCode: Int32?
    var activeActionName: String?
    var activeWebURL: URL?
    var activeWebPort: Int?
    var missingTools: [ProjectTool] = []
    var startedAt: Date?
    var lastCommand: String?
    /// False after a run finishes until the user has looked at the result.
    var acknowledged = true

    var combinedLog: String {
        runs.map { run in
            "▶ \(run.actionName)\n\(run.output)"
        }.joined(separator: "\n\n")
    }
}

/// Top-level workspace tab, browser-style. The springboard is the pinned
/// home tab; each project opens as an app tab, optionally grouped with an
/// embedded web view tab when it serves a local UI.
enum WorkspaceTab: Hashable, Identifiable {
    case springboard
    case ollama
    case app(AirstripProject.ID)
    case web(AirstripProject.ID)

    var id: String {
        switch self {
        case .springboard:
            return "springboard"
        case .ollama:
            return "ollama"
        case .app(let id):
            return "app-\(id.uuidString)"
        case .web(let id):
            return "web-\(id.uuidString)"
        }
    }

    var projectID: AirstripProject.ID? {
        switch self {
        case .springboard, .ollama:
            return nil
        case .app(let id), .web(let id):
            return id
        }
    }

    var isWeb: Bool {
        if case .web = self { return true }
        return false
    }
}

/// User-facing summary of what a project is doing right now.
enum ProjectDisplayStatus: Equatable {
    case idle
    case preparing
    case running
    case finished
    case needsAttention(Int32)

    init(_ state: ProjectRuntimeState) {
        if state.isPreparing {
            self = .preparing
        } else if state.isRunning {
            self = .running
        } else if let code = state.lastExitCode {
            self = code == 0 ? .finished : .needsAttention(code)
        } else {
            self = .idle
        }
    }

    var label: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Checking..."
        case .running:
            return "Running"
        case .finished:
            return "Finished"
        case .needsAttention:
            return "Needs attention"
        }
    }
}

struct RunningWebServer: Identifiable, Equatable {
    var id: AirstripProject.ID
    var project: AirstripProject
    var actionName: String?
    var url: URL
    var port: Int
}

enum DependencyStatus: Equatable {
    case unknown
    case available(String)
    case missing

    var label: String {
        switch self {
        case .unknown:
            return "Checking"
        case .available(let version):
            return version
        case .missing:
            return "Missing"
        }
    }
}
