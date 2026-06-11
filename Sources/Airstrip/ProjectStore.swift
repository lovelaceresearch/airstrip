import AppKit
import Darwin
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [AirstripProject] = []
    @Published var runtimeStates: [AirstripProject.ID: ProjectRuntimeState] = [:]
    @Published var lastError: String?

    private var processes: [AirstripProject.ID: Process] = [:]
    private var projectsFolderSource: DispatchSourceFileSystemObject?
    private var projectsFolderDescriptor: CInt = -1
    private var pendingSyncTask: Task<Void, Never>?
    private let fileManager = FileManager.default

    /// Apps launched from Finder get a minimal PATH, so Homebrew tools
    /// (ollama, pdftoppm, ...) would be invisible without this.
    nonisolated static let extendedPATH: String = {
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let extra = ["/opt/homebrew/bin", "/usr/local/bin"].filter { !current.contains($0) }
        return (extra + [current]).joined(separator: ":")
    }()

    /// Folder content that should never be copied into the Airstrip workspace.
    private static let importExclusions: Set<String> = [
        ".airstrip-venv", ".venv", "venv", "__pycache__", ".git",
        ".DS_Store", "node_modules", ".mypy_cache", ".pytest_cache", ".cache"
    ]

    var appSupportURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Airstrip", isDirectory: true)
    }

    private var projectsURL: URL {
        appSupportURL.appendingPathComponent("Projects", isDirectory: true)
    }

    private var indexURL: URL {
        appSupportURL.appendingPathComponent("projects.json")
    }

    var runningWebServers: [RunningWebServer] {
        projects.compactMap { project in
            guard let state = runtimeStates[project.id],
                  state.isRunning,
                  let url = state.activeWebURL,
                  let port = state.activeWebPort else {
                return nil
            }

            return RunningWebServer(
                id: project.id,
                project: project,
                actionName: state.activeActionName,
                url: url,
                port: port
            )
        }
    }

    func load() {
        do {
            try ensureDirectories()
            guard fileManager.fileExists(atPath: indexURL.path) else {
                projects = []
                syncProjectsWithWorkspace()
                startProjectsFolderMonitor()
                return
            }

            let data = try Data(contentsOf: indexURL)
            projects = try JSONDecoder.airstrip.decode([AirstripProject].self, from: data)
        } catch {
            projects = []
            appendSystemLog("Failed to load projects: \(error.localizedDescription)")
        }
        syncProjectsWithWorkspace()
        startProjectsFolderMonitor()
    }

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"

        guard panel.runModal() == .OK else { return }
        panel.urls.forEach { importProject(from: $0) }
    }

    func importFromDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                guard let url = Self.url(fromDroppedItem: item) else { return }

                Task { @MainActor in
                    self?.importProject(from: url)
                }
            }
        }
        return accepted
    }

    nonisolated private static func url(fromDroppedItem item: Any?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string) ?? URL(fileURLWithPath: string)
        }

        return nil
    }

    func toggle(_ project: AirstripProject) {
        if runtimeStates[project.id]?.isRunning == true {
            stop(project)
        } else {
            run(project, action: defaultAction(for: project))
        }
    }

    func run(_ project: AirstripProject, action: ProjectAction? = nil) {
        guard processes[project.id] == nil, runtimeStates[project.id]?.isPreparing != true else { return }

        let tools = project.manifest.tools ?? []
        guard !tools.isEmpty else {
            launch(project, action: action)
            return
        }

        var state = runtimeStates[project.id] ?? ProjectRuntimeState()
        state.isPreparing = true
        state.missingTools = []
        runtimeStates[project.id] = state

        Task {
            let missing = await Self.missingTools(tools)
            var state = runtimeStates[project.id] ?? ProjectRuntimeState()
            state.isPreparing = false
            state.missingTools = missing
            runtimeStates[project.id] = state

            if missing.isEmpty {
                launch(project, action: action)
            } else {
                let names = missing.map(\.command).joined(separator: ", ")
                appendLog("Missing required tools: \(names). Install them below, then run again.\n", for: project.id)
            }
        }
    }

    func dismissMissingTools(for project: AirstripProject) {
        var state = runtimeStates[project.id] ?? ProjectRuntimeState()
        state.missingTools = []
        runtimeStates[project.id] = state
    }

    private nonisolated static func missingTools(_ tools: [ProjectTool]) async -> [ProjectTool] {
        await Task.detached(priority: .userInitiated) {
            tools.filter { tool in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", "command -v \(tool.command.shellQuoted)"]
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = extendedPATH
                process.environment = environment
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    return process.terminationStatus != 0
                } catch {
                    return true
                }
            }
        }.value
    }

    private func launch(_ project: AirstripProject, action: ProjectAction? = nil) {
        guard processes[project.id] == nil else { return }

        let action = action ?? defaultAction(for: project)
        let webLaunch = resolvedWebLaunch(for: action, projectID: project.id)
        guard webLaunch.canRun else { return }

        let command = resolvedRunCommand(for: project, action: action, webPort: webLaunch.port)
        var state = runtimeStates[project.id] ?? ProjectRuntimeState()
        state.isRunning = true
        state.lastExitCode = nil
        state.activeActionName = action?.name
        state.activeWebURL = webLaunch.url
        state.activeWebPort = webLaunch.port
        state.log += "\n$ \(command)\n"
        runtimeStates[project.id] = state

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = project.path
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.extendedPATH
        if let port = webLaunch.port {
            environment["PORT"] = "\(port)"
            environment["AIRSTRIP_PORT"] = "\(port)"
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor in
                self?.appendLog(text, for: project.id)
            }
        }

        process.terminationHandler = { [weak self] process in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor in
                self?.processes[project.id] = nil
                var state = self?.runtimeStates[project.id] ?? ProjectRuntimeState()
                state.isRunning = false
                state.lastExitCode = process.terminationStatus
                state.log += "\nProcess exited with code \(process.terminationStatus).\n"
                self?.runtimeStates[project.id] = state
            }
        }

        do {
            try process.run()
            processes[project.id] = process
            if let url = webLaunch.url, webLaunch.openOnStart {
                openWebURLWhenReady(url, projectID: project.id)
            }
        } catch {
            processes[project.id] = nil
            var state = runtimeStates[project.id] ?? ProjectRuntimeState()
            state.isRunning = false
            state.lastExitCode = -1
            state.log += "Failed to run: \(error.localizedDescription)\n"
            runtimeStates[project.id] = state
        }
    }

    func stop(_ project: AirstripProject) {
        guard let process = processes[project.id] else { return }
        if let port = runtimeStates[project.id]?.activeWebPort {
            killPort(port)
        }

        // Process puts the child in its own process group, so signaling the
        // negative pid stops the whole tree (zsh plus python etc), not just
        // the shell. terminate() alone leaves grandchildren running.
        let pid = process.processIdentifier
        if pid > 0 {
            kill(-pid, SIGTERM)
        } else {
            process.terminate()
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            if process.isRunning, pid > 0 {
                kill(-pid, SIGKILL)
            }
        }
    }

    func openWebUI(for project: AirstripProject) {
        guard let url = runtimeStates[project.id]?.activeWebURL else { return }
        NSWorkspace.shared.open(url)
    }

    func openWebUI(_ server: RunningWebServer) {
        NSWorkspace.shared.open(server.url)
    }

    func stopWebServer(_ server: RunningWebServer) {
        stop(server.project)
    }

    func remove(_ project: AirstripProject) {
        if runtimeStates[project.id]?.isRunning == true {
            stop(project)
        }

        do {
            if fileManager.fileExists(atPath: project.path.path) {
                _ = try fileManager.trashItem(at: project.path, resultingItemURL: nil)
            }
        } catch {
            appendSystemLog("Failed to move \(project.name) to Trash: \(error.localizedDescription)")
        }

        projects.removeAll { $0.id == project.id }
        runtimeStates[project.id] = nil
        processes[project.id] = nil
        save()
    }

    func revealAirstripFolder() {
        do {
            try ensureDirectories()
            NSWorkspace.shared.open(projectsURL)
        } catch {
            appendSystemLog("Failed to reveal Airstrip folder: \(error.localizedDescription)")
        }
    }

    func refreshProjectsFromDisk() {
        syncProjectsWithWorkspace()
    }

    private func importProject(from sourceURL: URL) {
        do {
            try ensureDirectories()

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return
            }

            let manifest = loadManifest(from: sourceURL)
            let displayName = manifest.name ?? sourceURL.deletingPathExtension().lastPathComponent
            let destination = uniqueDestinationURL(for: displayName)

            try copyProjectFolder(from: sourceURL, to: destination)

            let copiedManifest = loadManifest(from: destination)
            let project = AirstripProject(
                name: copiedManifest.name ?? displayName,
                path: destination,
                manifest: copiedManifest
            )
            projects.append(project)
            runtimeStates[project.id] = ProjectRuntimeState()
            save()
            syncProjectsWithWorkspace()
        } catch {
            appendSystemLog("Failed to import \(sourceURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func syncProjectsWithWorkspace() {
        do {
            try ensureDirectories()

            let folderURLs = try fileManager.contentsOfDirectory(
                at: projectsURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { url in
                ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
            }

            let foldersByPath = Dictionary(uniqueKeysWithValues: folderURLs.map { ($0.standardizedFileURL.path, $0) })
            var seenPaths = Set<String>()
            var synced: [AirstripProject] = []

            for project in projects {
                let path = project.path.standardizedFileURL.path
                guard let folderURL = foldersByPath[path] else {
                    if runtimeStates[project.id]?.isRunning == true {
                        stop(project)
                    }
                    runtimeStates[project.id] = nil
                    processes[project.id] = nil
                    continue
                }

                var updated = project
                let manifest = loadManifest(from: folderURL)
                updated.path = folderURL
                updated.manifest = manifest
                updated.name = manifest.name ?? folderURL.lastPathComponent
                synced.append(updated)
                seenPaths.insert(path)
            }

            for folderURL in folderURLs {
                let path = folderURL.standardizedFileURL.path
                guard !seenPaths.contains(path) else { continue }

                let manifest = loadManifest(from: folderURL)
                let project = AirstripProject(
                    name: manifest.name ?? folderURL.lastPathComponent,
                    path: folderURL,
                    manifest: manifest
                )
                synced.append(project)
                runtimeStates[project.id] = runtimeStates[project.id] ?? ProjectRuntimeState()
            }

            if synced != projects {
                projects = synced.sorted { $0.createdAt < $1.createdAt }
                save()
            }
        } catch {
            appendSystemLog("Failed to sync Airstrip projects: \(error.localizedDescription)")
        }
    }

    private func startProjectsFolderMonitor() {
        guard projectsFolderSource == nil else { return }

        let descriptor = open(projectsURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            appendSystemLog("Failed to watch Airstrip projects folder.")
            return
        }

        projectsFolderDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleProjectSync()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        projectsFolderSource = source
        source.resume()
    }

    private func scheduleProjectSync() {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.syncProjectsWithWorkspace()
            }
        }
    }

    /// Copies a project folder while skipping virtualenvs, caches, and VCS
    /// folders. Carried-over venvs from another machine are broken anyway,
    /// and caches make the import slow and huge for no benefit.
    private func copyProjectFolder(from source: URL, to destination: URL) throws {
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        let contents = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        )

        for item in contents {
            let name = item.lastPathComponent
            if Self.importExclusions.contains(name) { continue }

            let target = destination.appendingPathComponent(name)
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                try copyProjectFolder(from: item, to: target)
            } else {
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }

    private func loadManifest(from folder: URL) -> ProjectManifest {
        let manifestURL = folder.appendingPathComponent("airstrip.json")
        guard fileManager.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL) else {
            return inferredManifest(from: folder)
        }

        do {
            return try JSONDecoder.airstrip.decode(ProjectManifest.self, from: data)
        } catch {
            appendSystemLog("airstrip.json in \(folder.lastPathComponent) is invalid (\(error.localizedDescription)). Using inferred commands instead.")
            return inferredManifest(from: folder)
        }
    }

    private func inferredManifest(from folder: URL) -> ProjectManifest {
        let names = ["main.py", "app.py", "streamlit_app.py"]
        let runFile = names.first { fileManager.fileExists(atPath: folder.appendingPathComponent($0).path) }
        let requirements = fileManager.fileExists(atPath: folder.appendingPathComponent("requirements.txt").path) ? "requirements.txt" : nil
        let actions = inferredActions(from: folder)

        return ProjectManifest(
            name: folder.deletingPathExtension().lastPathComponent,
            icon: nil,
            run: actions.first?.command ?? runFile.map { "python \($0)" },
            actions: actions.isEmpty ? nil : actions,
            requirements: requirements,
            ollama: nil
        )
    }

    func actions(for project: AirstripProject) -> [ProjectAction] {
        if let actions = project.manifest.actions, !actions.isEmpty {
            return actions
        }

        if let run = project.manifest.run, !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [ProjectAction(name: "Run", command: run, isDefault: true)]
        }

        return [ProjectAction(name: "Run", command: "python main.py", isDefault: true)]
    }

    func defaultAction(for project: AirstripProject) -> ProjectAction? {
        let actions = actions(for: project)
        return actions.first { $0.isDefault } ?? actions.first
    }

    private func resolvedRunCommand(for project: AirstripProject, action: ProjectAction?, webPort: Int? = nil) -> String {
        var commands: [String] = []
        let actionCommand: String

        if let action {
            actionCommand = replacePortPlaceholder(in: action.command, port: webPort)
        } else if let run = project.manifest.run, !run.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actionCommand = replacePortPlaceholder(in: run, port: webPort)
        } else {
            actionCommand = "python main.py"
        }

        if needsPythonRuntime(command: actionCommand, manifest: project.manifest) {
            commands.append("if ! command -v python3 >/dev/null 2>&1; then echo 'Airstrip needs python3 to run this project. Use Install Python in the sidebar.'; exit 127; fi")
            // A venv copied from another machine points at a python that does
            // not exist here; detect and rebuild instead of failing cryptically.
            commands.append("if [ -d .airstrip-venv ] && ! .airstrip-venv/bin/python -c '' >/dev/null 2>&1; then echo 'Rebuilding Python environment...'; rm -rf .airstrip-venv; fi")
            commands.append("if [ ! -d .airstrip-venv ]; then echo 'Creating Python environment...'; python3 -m venv .airstrip-venv; fi")
            commands.append("source .airstrip-venv/bin/activate")
        }

        if let requirements = project.manifest.requirements, !requirements.isEmpty {
            let quoted = requirements.shellQuoted
            commands.append("if [ ! -f \(quoted) ]; then echo \"Requirements file \(requirements) is missing.\"; exit 1; fi")
            // Reinstalling on every run costs 5-30s and needs network. Skip
            // when the requirements file has not changed since the last install.
            commands.append("""
            if ! cmp -s \(quoted) .airstrip-venv/.requirements-installed 2>/dev/null; then \
            echo 'Installing Python packages...'; \
            python -m pip install --quiet --upgrade pip && \
            python -m pip install --quiet -r \(quoted) && \
            cp \(quoted) .airstrip-venv/.requirements-installed; \
            fi
            """)
        }

        for model in project.manifest.ollama?.models ?? [] {
            commands.append("ollama pull \(model.shellQuoted)")
        }

        commands.append(actionCommand)

        return commands.joined(separator: " && ")
    }

    private func needsPythonRuntime(command: String, manifest: ProjectManifest) -> Bool {
        if let requirements = manifest.requirements, !requirements.isEmpty {
            return true
        }

        let pythonPrefixes = [
            "python ",
            "python3 ",
            "python -m ",
            "python3 -m "
        ]
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if pythonPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            return true
        }

        return trimmed.contains(" python ") || trimmed.contains(" python3 ")
    }

    private func resolvedWebLaunch(for action: ProjectAction?, projectID: AirstripProject.ID) -> WebLaunch {
        guard let web = action?.web else {
            return WebLaunch(canRun: true, port: nil, url: nil, openOnStart: false)
        }

        let requestedPort = web.port
        let allowFallback = web.allowPortFallback ?? true
        let port: Int

        if isPortAvailable(requestedPort) {
            port = requestedPort
        } else if allowFallback, let fallback = firstAvailablePort(startingAt: requestedPort + 1, limit: 50) {
            port = fallback
            appendLog("Port \(requestedPort) is busy. Using \(fallback) instead.\n", for: projectID)
        } else {
            appendLog("Port \(requestedPort) is already in use. Stop the other app or enable port fallback.\n", for: projectID)
            return WebLaunch(canRun: false, port: nil, url: nil, openOnStart: false)
        }

        let path = web.openPath ?? "/"
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let url = URL(string: "http://localhost:\(port)\(normalizedPath)")
        return WebLaunch(canRun: true, port: port, url: url, openOnStart: web.openOnStart ?? true)
    }

    private func replacePortPlaceholder(in command: String, port: Int?) -> String {
        guard let port else { return command }
        return command.replacingOccurrences(of: "{PORT}", with: "\(port)")
    }

    private func firstAvailablePort(startingAt start: Int, limit: Int) -> Int? {
        for port in start..<(start + limit) where isPortAvailable(port) {
            return port
        }
        return nil
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { return false }
        defer { close(socketDescriptor) }

        var value: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    private func openWebURLWhenReady(_ url: URL, projectID: AirstripProject.ID) {
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                if runtimeStates[projectID]?.isRunning == true {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func killPort(_ port: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "pids=$(lsof -ti tcp:\(port)); if [ -n \"$pids\" ]; then kill $pids; fi"]
        try? process.run()
    }

    private func inferredActions(from folder: URL) -> [ProjectAction] {
        if let readmeActions = readmeActions(from: folder), !readmeActions.isEmpty {
            return readmeActions
        }

        if fileManager.fileExists(atPath: folder.appendingPathComponent("app/main.py").path) {
            return [ProjectAction(name: "Run CLI", command: "python -m app.main", isDefault: true)]
        }

        return []
    }

    private func readmeActions(from folder: URL) -> [ProjectAction]? {
        let candidates = ["README.md", "readme.md", "Readme.md"]
        guard let readme = candidates
            .map({ folder.appendingPathComponent($0) })
            .first(where: { fileManager.fileExists(atPath: $0.path) }),
            let text = try? String(contentsOf: readme, encoding: .utf8) else {
            return nil
        }

        let lines = text.components(separatedBy: .newlines)
        let commands = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("python ") || trimmed.hasPrefix("python3 ") else { return nil }
            if trimmed.hasPrefix("python3 ") {
                return "python " + trimmed.dropFirst("python3 ".count)
            }
            return trimmed
        }

        let uniqueCommands = commands.reduce(into: [String]()) { result, command in
            if !result.contains(command) {
                result.append(command)
            }
        }

        return uniqueCommands.enumerated().map { index, command in
            ProjectAction(
                name: actionName(for: command, index: index),
                command: command,
                isDefault: index == 0
            )
        }
    }

    private func actionName(for command: String, index: Int) -> String {
        if command.contains("--email"), command.contains("--json") {
            return "Compare JSON"
        }

        if command.contains("--email") {
            return "Compare Email"
        }

        if command.contains(".pdf") {
            return "Extract PDF"
        }

        return "Command \(index + 1)"
    }

    private func uniqueDestinationURL(for name: String) -> URL {
        let slug = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var candidate = projectsURL.appendingPathComponent(slug.isEmpty ? "Project" : slug, isDirectory: true)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = projectsURL.appendingPathComponent("\(slug)-\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: projectsURL, withIntermediateDirectories: true)
    }

    private func save() {
        do {
            try ensureDirectories()
            let data = try JSONEncoder.airstrip.encode(projects)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            appendSystemLog("Failed to save projects: \(error.localizedDescription)")
        }
    }

    private static let maxLogLength = 200_000

    private func appendLog(_ text: String, for id: AirstripProject.ID) {
        var state = runtimeStates[id] ?? ProjectRuntimeState()
        state.log += text
        if state.log.count > Self.maxLogLength {
            state.log = "[older output trimmed]\n" + state.log.suffix(Self.maxLogLength * 3 / 4)
        }
        runtimeStates[id] = state
    }

    private func appendSystemLog(_ text: String) {
        print("[Airstrip] \(text)")
        lastError = text
    }
}

private struct WebLaunch {
    var canRun: Bool
    var port: Int?
    var url: URL?
    var openOnStart: Bool
}

private extension JSONEncoder {
    static var airstrip: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var airstrip: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
