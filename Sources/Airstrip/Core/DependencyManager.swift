import AppKit
import Foundation

@MainActor
final class DependencyManager: ObservableObject {
    @Published var python: DependencyStatus = .unknown
    @Published var node: DependencyStatus = .unknown
    @Published var homebrew: DependencyStatus = .unknown
    @Published var ollama: DependencyStatus = .unknown
    @Published var isDownloadingOllama = false
    @Published var ollamaDownloadTargetURL: URL?
    @Published var ollamaDownloadError: String?

    func refresh() {
        python = .unknown
        node = .unknown
        homebrew = .unknown
        ollama = .unknown

        Task {
            async let pythonResult = Self.version(command: "python3 --version")
            async let nodeResult = Self.version(command: "node --version && npm --version")
            async let brewResult = Self.version(command: "brew --version | head -n 1")
            async let ollamaResult = Self.version(command: "ollama --version")

            python = await pythonResult
            node = await nodeResult
            homebrew = await brewResult
            ollama = await ollamaResult
        }
    }

    func installHomebrew() {
        runVisibleTerminalCommand("""
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        """)
    }

    func installOllama() {
        guard !isDownloadingOllama else { return }

        isDownloadingOllama = true
        ollamaDownloadTargetURL = nil
        ollamaDownloadError = nil

        Task {
            do {
                let source = URL(string: "https://ollama.com/download/Ollama.dmg")!
                let (temporaryURL, response) = try await URLSession.shared.download(from: source)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }

                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                let targetURL = uniqueFileURL(in: downloadsURL, filename: "Ollama.dmg")
                try? FileManager.default.removeItem(at: targetURL)
                try FileManager.default.moveItem(at: temporaryURL, to: targetURL)

                isDownloadingOllama = false
                ollamaDownloadTargetURL = targetURL
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                refresh()
            } catch {
                isDownloadingOllama = false
                ollamaDownloadError = "Ollama download failed: \(error.localizedDescription)"
                NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
            }
        }
    }

    func installPython() {
        if case .available = homebrew {
            runVisibleTerminalCommand("brew install python")
        } else {
            NSWorkspace.shared.open(URL(string: "https://www.python.org/downloads/macos/")!)
        }
    }

    func installNode() {
        if case .available = homebrew {
            runVisibleTerminalCommand("brew install node")
        } else {
            NSWorkspace.shared.open(URL(string: "https://nodejs.org/en/download")!)
        }
    }

    /// Installs a Homebrew package in a visible Terminal window, bootstrapping
    /// Homebrew itself first when it is not installed yet. This keeps the
    /// "missing tool" fix to a single click for non-technical users.
    func installBrewPackage(_ package: String) {
        let script = """
        if ! command -v brew >/dev/null 2>&1 && [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"; fi; \
        if ! command -v brew >/dev/null 2>&1 && [ -x /usr/local/bin/brew ]; then eval "$(/usr/local/bin/brew shellenv)"; fi; \
        if ! command -v brew >/dev/null 2>&1; then \
        echo 'Installing Homebrew first...'; \
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && \
        eval "$([ -x /opt/homebrew/bin/brew ] && /opt/homebrew/bin/brew shellenv || /usr/local/bin/brew shellenv)"; \
        fi; \
        brew install \(package)
        """
        runVisibleTerminalCommand(script)
    }

    /// Runs a command in a visible Terminal window by opening a temporary
    /// `.command` file. Unlike AppleScript's `do script`, this needs no
    /// Apple Events entitlement or automation consent, so it works in any
    /// build instead of opening an empty Terminal window when permission
    /// is silently denied.
    private func runVisibleTerminalCommand(_ command: String) {
        let script = """
        #!/bin/zsh
        clear
        echo "Airstrip installer"
        echo "------------------"
        \(command)
        status=$?
        echo
        if [ $status -eq 0 ]; then
            echo "Done. You can close this window and go back to Airstrip."
        else
            echo "Installation failed with exit code $status. Scroll up for details."
        fi
        exit $status
        """

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Airstrip Install \(UUID().uuidString.prefix(8)).command")

        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            print("[Airstrip] Failed to open installer in Terminal: \(error.localizedDescription)")
        }
    }

    private static func version(command: String) async -> DependencyStatus {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ProjectStore.extendedPATH
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard process.terminationStatus == 0, !output.isEmpty else {
                    return .missing
                }
                return .available(output.components(separatedBy: "\n").first ?? output)
            } catch {
                return .missing
            }
        }.value
    }

    private func uniqueFileURL(in folder: URL, filename: String) -> URL {
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = folder.appendingPathComponent(filename)
        var index = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            candidate = folder.appendingPathComponent(numbered)
            index += 1
        }

        return candidate
    }
}
