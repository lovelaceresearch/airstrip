import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dashboard header

/// Overview cards above the app grid: runtime health, current activity,
/// and a guide to what Airstrip can run (with a folder checker).
struct DashboardHeader: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @EnvironmentObject private var ollama: OllamaManager

    @State private var showGuide = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            runtimeCard
            activityCard
            guideCard
        }
        .sheet(isPresented: $showGuide) {
            CapabilityGuideSheet()
        }
    }

    // MARK: Runtime card

    private var runtimeCard: some View {
        DashboardCard(title: "Runtime", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 8) {
                runtimeLine("Python", status: dependencyManager.python, install: dependencyManager.installPython)
                runtimeLine("Homebrew", status: dependencyManager.homebrew, install: dependencyManager.installHomebrew)
                runtimeLine("Ollama", status: dependencyManager.ollama, install: dependencyManager.installOllama)

                Divider()

                OllamaServerSwitch()
            }
        }
    }

    private func runtimeLine(_ name: String, status: DependencyStatus, install: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 7, height: 7)

            Text(name)
                .font(.system(size: 11.5))

            Spacer()

            switch status {
            case .unknown:
                Text("Checking...")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            case .available(let version):
                Text(shortVersion(version))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .missing:
                Button("Install", action: install)
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .font(.system(size: 10.5, weight: .medium))
            }
        }
    }

    private func statusColor(_ status: DependencyStatus) -> Color {
        switch status {
        case .unknown: return .yellow
        case .available: return .green
        case .missing: return .orange
        }
    }

    /// "Python 3.12.4" instead of the full version banner.
    private func shortVersion(_ version: String) -> String {
        let parts = version.components(separatedBy: " ")
        if parts.count >= 2 {
            return parts.prefix(2).joined(separator: " ")
        }
        return version
    }

    // MARK: Activity card

    private var runningCount: Int {
        store.projects.filter {
            let state = store.runtimeStates[$0.id]
            return state?.isRunning == true || state?.isPreparing == true
        }.count
    }

    private var attentionCount: Int {
        store.projects.filter {
            let state = store.runtimeStates[$0.id]
            guard let state, !state.acknowledged else { return false }
            if case .needsAttention = ProjectDisplayStatus(state) {
                return true
            }
            return false
        }.count
    }

    private var activityCard: some View {
        DashboardCard(title: "Activity", systemImage: "bolt") {
            VStack(alignment: .leading, spacing: 8) {
                activityLine(
                    icon: "play.circle.fill",
                    color: runningCount > 0 ? .green : .secondary,
                    text: runningCount == 1 ? "1 app running" : "\(runningCount) apps running"
                )

                activityLine(
                    icon: attentionCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle",
                    color: attentionCount > 0 ? .orange : .secondary,
                    text: attentionCount == 0
                        ? "Nothing needs attention"
                        : (attentionCount == 1 ? "1 result to check" : "\(attentionCount) results to check")
                )

                activityLine(
                    icon: "square.grid.3x3",
                    color: .secondary,
                    text: store.projects.count == 1 ? "1 app installed" : "\(store.projects.count) apps installed"
                )

                if ollama.serverStatus.isRunning {
                    activityLine(icon: "sparkles", color: .teal, text: "AI Studio ready")
                }
            }
        }
    }

    private func activityLine(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 14)

            Text(text)
                .font(.system(size: 11.5))

            Spacer(minLength: 0)
        }
    }

    // MARK: Guide card

    private var guideCard: some View {
        DashboardCard(title: "What Can I Run?", systemImage: "questionmark.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Python scripts, command-line tools, and local web apps — dropped in as folders, launched as icons.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button {
                        showGuide = true
                    } label: {
                        Label("Guide", systemImage: "book")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        showGuide = true
                        // The sheet opens with the checker section visible.
                    } label: {
                        Label("Check a Folder", systemImage: "folder.badge.questionmark")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

// MARK: - Capability guide sheet

/// Full-size explanation of what Airstrip can and cannot run, with concrete
/// examples and a folder checker that grades any folder before importing.
struct CapabilityGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("What Airstrip Can Run")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    guideSection

                    Divider()

                    FolderCheckerSection()
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 620)
    }

    private var guideSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            capabilityRow(
                icon: "checkmark.circle.fill", color: .green,
                title: "Python automations",
                detail: "Scripts with a requirements.txt. Airstrip creates a private Python environment per app and installs packages automatically. Example: a folder with app.py and requirements.txt."
            )

            capabilityRow(
                icon: "checkmark.circle.fill", color: .green,
                title: "Local web apps",
                detail: "Streamlit, Flask, FastAPI, or anything that serves a port. The app opens in a built-in browser tab. Example: streamlit run app.py --server.port $PORT."
            )

            capabilityRow(
                icon: "checkmark.circle.fill", color: .green,
                title: "Command-line tools",
                detail: "Any shell command declared in airstrip.json. Extra tools (like poppler for PDF work) install with one click when the manifest declares them."
            )

            capabilityRow(
                icon: "checkmark.circle.fill", color: .green,
                title: "AI-powered automations",
                detail: "Apps that use local Ollama models. Airstrip checks the models are downloaded before running. Cloud keys (OpenAI, Gemini, Claude, Mistral) work in AI Studio."
            )

            capabilityRow(
                icon: "xmark.circle.fill", color: .red,
                title: "What does not work",
                detail: "Windows or Linux binaries, folders with no runnable command and no recognizable entry point, and apps that need other languages' runtimes (Node, Ruby...) unless already installed."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("The ideal app folder")
                    .font(.system(size: 12, weight: .semibold))

                Text("""
                my-automation/
                ├─ airstrip.json      ← name, run command, actions
                ├─ requirements.txt   ← Python packages
                ├─ app.py             ← the program
                └─ icon.png           ← optional icon
                """)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

                Text("No airstrip.json? Airstrip still tries: it reads the README for commands and looks for app.py or main.py.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func capabilityRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Folder checker

private struct FolderCheckerSection: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager

    @State private var checkedFolder: URL?
    @State private var results: [FolderCheckResult] = []
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check a Folder")
                        .font(.system(size: 13, weight: .semibold))

                    Text("Grade any folder before importing it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    pickFolder()
                } label: {
                    Label("Choose Folder...", systemImage: "folder.badge.questionmark")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isChecking)
            }

            if isChecking {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Checking \(checkedFolder?.lastPathComponent ?? "folder")...")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            } else if let folder = checkedFolder, !results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    verdictBanner

                    ForEach(results) { result in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: result.kind.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(result.kind.color)
                                .frame(width: 16)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.title)
                                    .font(.system(size: 11.5, weight: .medium))

                                if !result.detail.isEmpty {
                                    Text(result.detail)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                    }

                    if verdict != .fail {
                        Button {
                            store.importProject(from: folder)
                        } label: {
                            Label("Import \(folder.lastPathComponent)", systemImage: "plus.app")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var verdict: FolderCheckResult.Kind {
        if results.contains(where: { $0.kind == .fail }) { return .fail }
        if results.contains(where: { $0.kind == .warn }) { return .warn }
        return .pass
    }

    private var verdictBanner: some View {
        let (text, color): (String, Color) = {
            switch verdict {
            case .pass: return ("Ready to run in Airstrip", .green)
            case .warn: return ("Should run, with caveats", .orange)
            case .fail: return ("Needs changes before it can run", .red)
            case .info: return ("Checked", .secondary)
            }
        }()

        return Label(text, systemImage: verdict.icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder to check whether Airstrip can run it"
        panel.prompt = "Check"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        checkedFolder = url
        isChecking = true
        results = []

        let python = dependencyManager.python
        let ollamaStatus = dependencyManager.ollama
        Task {
            let analysis = await FolderCheck.analyze(folder: url, python: python, ollama: ollamaStatus)
            results = analysis
            isChecking = false
        }
    }
}

struct FolderCheckResult: Identifiable {
    enum Kind {
        case pass, warn, fail, info

        var icon: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            case .info: return "info.circle"
            }
        }

        var color: Color {
            switch self {
            case .pass: return .green
            case .warn: return .orange
            case .fail: return .red
            case .info: return .secondary
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
}

/// Static analysis of a folder: manifest, run command, Python needs,
/// declared tools, and Ollama models — the same rules the launcher applies.
enum FolderCheck {
    static func analyze(folder: URL, python: DependencyStatus, ollama: DependencyStatus) async -> [FolderCheckResult] {
        var results: [FolderCheckResult] = []
        let fm = FileManager.default
        let manifestURL = folder.appendingPathComponent("airstrip.json")

        var manifest: ProjectManifest?
        if fm.fileExists(atPath: manifestURL.path) {
            do {
                let data = try Data(contentsOf: manifestURL)
                let decoded = try JSONDecoder().decode(ProjectManifest.self, from: data)
                manifest = decoded
                results.append(.init(
                    kind: .pass,
                    title: "airstrip.json is valid",
                    detail: decoded.name.map { "App name: \($0)" } ?? ""
                ))
            } catch {
                results.append(.init(
                    kind: .fail,
                    title: "airstrip.json is broken",
                    detail: error.localizedDescription
                ))
            }
        } else {
            let hints = entryPointHints(in: folder)
            if hints.isEmpty {
                results.append(.init(
                    kind: .fail,
                    title: "No airstrip.json and no recognizable entry point",
                    detail: "Add an airstrip.json with a run command, or include app.py / main.py."
                ))
            } else {
                results.append(.init(
                    kind: .warn,
                    title: "No airstrip.json — Airstrip will guess",
                    detail: "Found \(hints.joined(separator: ", ")). An airstrip.json makes the run command explicit."
                ))
            }
        }

        // Run command.
        if let manifest {
            let actionCount = manifest.actions?.count ?? 0
            if actionCount > 0 {
                let names = (manifest.actions ?? []).map(\.name).joined(separator: ", ")
                results.append(.init(
                    kind: .pass,
                    title: actionCount == 1 ? "1 action declared" : "\(actionCount) actions declared",
                    detail: names
                ))
            } else if let run = manifest.run, !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(.init(kind: .pass, title: "Run command declared", detail: run))
            } else {
                results.append(.init(
                    kind: .fail,
                    title: "Manifest has no run command",
                    detail: "Add a \"run\" field or an \"actions\" array to airstrip.json."
                ))
            }

            if manifest.actions?.contains(where: { $0.web != nil }) == true {
                results.append(.init(
                    kind: .info,
                    title: "Includes a web UI",
                    detail: "Opens in Airstrip's built-in browser tab when started."
                ))
            }
        }

        // Python runtime.
        let needsPython = manifestNeedsPython(manifest) || fm.fileExists(atPath: folder.appendingPathComponent("requirements.txt").path)
        if needsPython {
            switch python {
            case .available(let version):
                results.append(.init(kind: .pass, title: "Python is installed", detail: version))
            case .missing:
                results.append(.init(
                    kind: .fail,
                    title: "Needs Python, which is not installed",
                    detail: "Install it from the Runtime panel; everything else is automatic."
                ))
            case .unknown:
                results.append(.init(kind: .info, title: "Python status still being checked", detail: ""))
            }

            if let requirements = manifest?.requirements, !requirements.isEmpty {
                if fm.fileExists(atPath: folder.appendingPathComponent(requirements).path) {
                    results.append(.init(
                        kind: .pass,
                        title: "Packages install automatically",
                        detail: "From \(requirements) into a private environment."
                    ))
                } else {
                    results.append(.init(
                        kind: .fail,
                        title: "\(requirements) is declared but missing",
                        detail: "The manifest points to a requirements file that is not in the folder."
                    ))
                }
            }
        }

        // Declared command-line tools.
        if let tools = manifest?.tools, !tools.isEmpty {
            for tool in tools {
                let installed = await isCommandAvailable(tool.command)
                if installed {
                    results.append(.init(kind: .pass, title: "\(tool.command) is installed", detail: ""))
                } else {
                    results.append(.init(
                        kind: .warn,
                        title: "\(tool.command) is not installed yet",
                        detail: tool.brew.map { "Airstrip offers a one-click install (brew install \($0))." }
                            ?? "Airstrip will flag this before running."
                    ))
                }
            }
        }

        // Ollama models.
        if let models = manifest?.ollama?.models, !models.isEmpty {
            switch ollama {
            case .available:
                results.append(.init(
                    kind: .pass,
                    title: "Uses local AI models",
                    detail: "Needs: \(models.joined(separator: ", ")). Airstrip checks they are downloaded."
                ))
            case .missing:
                results.append(.init(
                    kind: .warn,
                    title: "Needs Ollama, which is not installed",
                    detail: "Models required: \(models.joined(separator: ", "))."
                ))
            case .unknown:
                results.append(.init(kind: .info, title: "Ollama status still being checked", detail: ""))
            }
        }

        return results
    }

    private static func entryPointHints(in folder: URL) -> [String] {
        let fm = FileManager.default
        var hints: [String] = []
        for candidate in ["app.py", "main.py", "app/main.py", "streamlit_app.py", "README.md"] {
            if fm.fileExists(atPath: folder.appendingPathComponent(candidate).path) {
                hints.append(candidate)
            }
        }
        return hints
    }

    private static func manifestNeedsPython(_ manifest: ProjectManifest?) -> Bool {
        guard let manifest else { return false }
        if let requirements = manifest.requirements, !requirements.isEmpty { return true }
        let commands = [manifest.run ?? ""] + (manifest.actions ?? []).map(\.command)
        return commands.contains { $0.contains("python") || $0.contains("streamlit") || $0.contains("uvicorn") }
    }

    private static func isCommandAvailable(_ command: String) async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            let quoted = "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
            process.arguments = ["-c", "command -v \(quoted) >/dev/null 2>&1"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ProjectStore.extendedPATH
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }.value
    }
}
