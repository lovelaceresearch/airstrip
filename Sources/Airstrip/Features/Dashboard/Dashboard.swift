import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Status sidebar

struct ActivePortsCard: View {
    @EnvironmentObject private var store: ProjectStore
    private let timer = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        DashboardCard(title: "Active Ports", systemImage: "network") {
            VStack(alignment: .leading, spacing: 8) {
                if store.activePorts.isEmpty {
                    Text("No active TCP ports in use (>= 80).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(store.activePorts) { info in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(info.isAirstripProject ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)

                                Text(":\(info.port)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 48, alignment: .leading)

                                VStack(alignment: .leading, spacing: 1) {
                                    if let projName = info.airstripProjectName {
                                        Text(projName)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                        Text("Airstrip App")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(info.processName ?? "Unknown")
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                        Text("PID \(info.pid ?? 0) • External")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer(minLength: 4)

                                if info.isAirstripProject {
                                    Button("Stop") {
                                        if let project = store.projects.first(where: { $0.name == info.airstripProjectName }) {
                                            store.stop(project)
                                        }
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.mini)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.red)
                                    .noFocusRing()
                                } else if let pid = info.pid {
                                    Button("Kill") {
                                        store.killProcess(pid: pid)
                                    }
                                    .buttonStyle(.borderless)
                                    .controlSize(.mini)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.orange)
                                    .noFocusRing()
                                }
                            }
                            
                            if info.port != store.activePorts.last?.port {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            store.refreshActivePorts()
        }
        .onReceive(timer) { _ in
            store.refreshActivePorts()
        }
    }
}

struct RunningAppsCard: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        let running = store.projects.filter {
            let state = store.runtimeStates[$0.id]
            return state?.isRunning == true || state?.isPreparing == true
        }

        DashboardCard(title: "Running Apps", systemImage: "play.circle") {
            VStack(alignment: .leading, spacing: 8) {
                if running.isEmpty {
                    Text("No apps running.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(running) { project in
                            let state = store.runtimeStates[project.id] ?? ProjectRuntimeState()
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(state.isPreparing ? Color.yellow : Color.green)
                                    .frame(width: 6, height: 6)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(project.name)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .lineLimit(1)

                                    if let action = state.activeActionName {
                                        Text(action)
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button("Stop") {
                                    store.stop(project)
                                }
                                .buttonStyle(.borderless)
                                .controlSize(.mini)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.red)
                                .noFocusRing()
                            }

                            if project.id != running.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RuntimeCard: View {
    @EnvironmentObject private var dependencyManager: DependencyManager
    @EnvironmentObject private var ollama: OllamaManager
    @State private var confirmingOllamaDownload = false

    var body: some View {
        DashboardCard(title: "Runtime", systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 8) {
                runtimeLine("Python", status: dependencyManager.python, install: dependencyManager.installPython)
                runtimeLine("Node/npm", status: dependencyManager.node, install: dependencyManager.installNode)
                runtimeLine("Homebrew", status: dependencyManager.homebrew, install: dependencyManager.installHomebrew)
                runtimeLine("Ollama", status: dependencyManager.ollama, install: { confirmingOllamaDownload = true }, actionLabel: "Download")

                if dependencyManager.isDownloadingOllama {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                        Text("Downloading Ollama from ollama.com...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else if let url = dependencyManager.ollamaDownloadTargetURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Ollama DMG downloaded", systemImage: "checkmark.circle")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.green)
                    .noFocusRing()
                } else if let error = dependencyManager.ollamaDownloadError {
                    Text(error)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                OllamaServerSwitch()
            }
        }
        .onAppear {
            ollama.refreshServerStatus()
        }
        .alert("Download Ollama?", isPresented: $confirmingOllamaDownload) {
            Button("Download") {
                dependencyManager.installOllama()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Airstrip will download the official macOS DMG from ollama.com into your Downloads folder. Open the DMG to finish installing Ollama.")
        }
    }

    private func runtimeLine(_ name: String, status: DependencyStatus, install: @escaping () -> Void, actionLabel: String = "Install") -> some View {
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
                Button(actionLabel, action: install)
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .font(.system(size: 10.5, weight: .medium))
                    .noFocusRing()
                    .disabled(name == "Ollama" && dependencyManager.isDownloadingOllama)
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

    private func shortVersion(_ version: String) -> String {
        let parts = version.components(separatedBy: " ")
        if parts.count >= 2 {
            return parts.prefix(2).joined(separator: " ")
        }
        return version
    }
}

struct HelpCard: View {
    @Binding var showGuide: Bool

    var body: some View {
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
                    .airstripGlassButton()
                    .controlSize(.small)
                    .noFocusRing()
                }
            }
        }
    }
}



struct StatusSidebar: View {
    @Environment(\.airstripVisualStyle) private var visualStyle
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @EnvironmentObject private var ollama: OllamaManager

    @State private var showGuide = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Status")
                                .font(.title2.weight(.semibold))

                            Text(summaryText)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Button {
                                store.refreshActivePorts()
                                dependencyManager.refresh()
                                ollama.refreshServerStatus()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Refresh status and ports")
                            .noFocusRing()

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    store.isSidebarOpen = false
                                }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Hide Sidebar")
                            .noFocusRing()
                        }
                    }

                    // top to bottom: running server/apps - runtime - help - allports
                    RunningAppsCard()
                    RuntimeCard()
                    HelpCard(showGuide: $showGuide)
                    ActivePortsCard()
                    DownloadsCard()
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
                .opacity(0.5)

            // Bottom fixed settings button
            HStack {
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13))
                        Text("Settings...")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .airstripGlassPanel(cornerRadius: 8, interactive: true, fallbackOpacity: 0.45)
                }
                .buttonStyle(.plain)
                .noFocusRing()
            }
            .padding(12)
        }
        .background(.bar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(.separator.opacity(visualStyle.separatorOpacity))
                .frame(width: 1)
        }
        .sheet(isPresented: $showGuide) {
            CapabilityGuideSheet()
        }
        .sheet(isPresented: $showSettings) {
            AISettingsSheet()
                .environmentObject(ollama)
        }
    }

    private var summaryText: String {
        let running = store.projects.filter {
            let state = store.runtimeStates[$0.id]
            return state?.isRunning == true || state?.isPreparing == true
        }.count

        if [dependencyManager.python, dependencyManager.node, dependencyManager.homebrew, dependencyManager.ollama].contains(.unknown) {
            return "Checking local tools..."
        }
        if running > 0 {
            return running == 1 ? "1 folder is running." : "\(running) folders are running."
        }
        if ollama.serverStatus.isRunning {
            return "Runtime ready. Airo is available."
        }
        return "Runtime, activity, and runability."
    }
}

struct DownloadsCard: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        if !store.downloads.isEmpty {
            DashboardCard(title: "Downloads", systemImage: "arrow.down.circle") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.downloads) { download in
                        downloadRow(download)
                    }

                    HStack {
                        Spacer()
                        Button("Clear List") {
                            store.clearDownloads()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .noFocusRing()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func downloadRow(_ download: AirstripDownload) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: fileIcon(for: download.filename))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text(download.filename)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if download.isCompleted {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([download.targetURL])
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                    .noFocusRing()
                } else if let error = download.errorDescription {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .help(error)
                } else {
                    Text("\(Int(download.progress * 100))%")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if !download.isCompleted && download.errorDescription == nil {
                ProgressView(value: download.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(height: 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func fileIcon(for filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "svg":
            return "photo"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "rar":
            return "doc.zipper"
        case "json", "js", "ts", "html", "css", "py":
            return "doc.text"
        default:
            return "doc"
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
        .airstripGlassPanel(cornerRadius: 12, fallbackOpacity: 0.5)
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
                    .noFocusRing()
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    guideSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, idealWidth: 560, maxWidth: 720, minHeight: 540, idealHeight: 620, maxHeight: 760)
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
                detail: "Streamlit, Flask, FastAPI, Vite, Next.js, static HTML, or anything that serves a port. The app opens in a built-in browser tab."
            )

            capabilityRow(
                icon: "checkmark.circle.fill", color: .green,
                title: "Command-line tools",
                detail: "Any shell command declared in airstrip.json. Extra tools (like poppler for PDF work) install with one click when the manifest declares them."
            )

            capabilityRow(
                icon: "checkmark.circle.fill", color: .green,
                title: "AI-powered automations",
                detail: "Apps that use local Ollama models. Airstrip checks the models are downloaded before running. Cloud keys (OpenAI, Gemini, Claude, Mistral) work in Airo."
            )

            capabilityRow(
                icon: "xmark.circle.fill", color: .red,
                title: "What does not work",
                detail: "Windows or Linux binaries, mobile apps, Docker-only repos, cloud-only backends, folders with no runnable command, and projects that need runtimes Airstrip cannot install or detect yet."
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

                Text("No airstrip.json? Airstrip still tries: it reads package.json scripts, serves index.html, reads README commands, and looks for app.py, main.py, streamlit_app.py, or app/main.py.")
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

struct FirstRunOnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var hasSeenOnboarding: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Set Up Airstrip")
                        .font(.title2.weight(.semibold))

                    Text("Check this Mac, then drop in a project folder.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RuntimeCard()

                    onboardingSection(
                        title: "Can Run",
                        icon: "checkmark.circle.fill",
                        tint: .green,
                        lines: [
                            "Python automations with requirements.txt.",
                            "Static HTML and local web apps such as Streamlit, Flask, FastAPI, Vite, and Next.js.",
                            "Shell commands declared in airstrip.json.",
                            "Ollama-backed projects that declare local model names."
                        ]
                    )

                    onboardingSection(
                        title: "Needs Preparation",
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        lines: [
                            "Folders with no clear run command.",
                            "Docker-only, mobile, cloud-only, Windows-only, or Linux-only projects.",
                            "Projects that require runtimes or system services Airstrip cannot install or detect yet."
                        ]
                    )
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()

                Button("Done") {
                    hasSeenOnboarding = true
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .noFocusRing()
            }
            .padding(16)
        }
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 760, minHeight: 620, idealHeight: 700, maxHeight: 820)
    }

    private func onboardingSection(title: String, icon: String, tint: Color = .accentColor, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(tint.opacity(0.75))
                            .frame(width: 5, height: 5)
                            .padding(.top, 6)

                        Text(line)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .airstripGlassPanel(cornerRadius: 10, tint: tint, fallbackOpacity: 0.35)
    }
}

struct ImportRunCheckerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ProjectStore

    let isChecking: Bool
    let checks: [AirstripRunCheck]

    private var importableChecks: [AirstripRunCheck] {
        checks.filter { $0.canImport }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checklist.checked")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Airstrip Run Checker")
                        .font(.title3.weight(.semibold))

                    Text(isChecking ? "Checking what this can run..." : summaryText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .noFocusRing()
            }
            .padding(18)

            Divider()

            if isChecking {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Reading the dropped item and checking local runtimes.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(checks) { check in
                            RunCheckCard(check: check)
                        }
                    }
                    .padding(18)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    copyGuides(checks)
                } label: {
                    Label("Copy Guide", systemImage: "doc.on.doc")
                }
                .airstripGlassButton()
                .disabled(checks.isEmpty)
                .noFocusRing()

                Spacer()

                Button {
                    addImportableItems()
                } label: {
                    Label(addButtonTitle, systemImage: "plus.app")
                }
                .airstripGlassButton(prominent: true)
                .disabled(importableChecks.isEmpty || isChecking)
                .noFocusRing()
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 860, minHeight: 560, idealHeight: 680, maxHeight: 820)
    }

    private var summaryText: String {
        if checks.isEmpty { return "No dropped item was readable." }
        let blocked = checks.filter { !$0.canImport }.count
        if blocked == 0 {
            return checks.count == 1 ? "Ready to add this item." : "Ready to add \(checks.count) items."
        }
        if importableChecks.isEmpty {
            return "This needs preparation before Airstrip can add it."
        }
        return "\(importableChecks.count) ready, \(blocked) need preparation."
    }

    private var addButtonTitle: String {
        importableChecks.count == 1 ? "Add to Airstrip" : "Add \(importableChecks.count) Items"
    }

    private func addImportableItems() {
        for check in importableChecks {
            store.importProject(from: check.url)
        }
        dismiss()
    }

    private func copyGuides(_ checks: [AirstripRunCheck]) {
        let text = checks.map(\.guideMarkdown).joined(separator: "\n\n---\n\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct RunCheckCard: View {
    let check: AirstripRunCheck

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: check.verdict.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(check.verdict.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(check.url.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(check.verdictTitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(check.verdict.color)
                }

                Spacer()

                Button {
                    copyGuide()
                } label: {
                    Label("Copy Guide", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .noFocusRing()
            }

            VStack(alignment: .leading, spacing: 7) {
                ForEach(check.results) { result in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: result.kind.icon)
                            .font(.system(size: 11))
                            .foregroundStyle(result.kind.color)
                            .frame(width: 14)
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
                    }
                }
            }

            if !check.canImport {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guide for Codex or Antigravity")
                        .font(.system(size: 11.5, weight: .semibold))

                    Text(check.guideMarkdown)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(16)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(14)
        .airstripGlassPanel(cornerRadius: 10, tint: check.verdict.color, fallbackOpacity: 0.35)
    }

    private func copyGuide() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(check.guideMarkdown, forType: .string)
    }
}

// MARK: - Run checker

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
    let blocksImport: Bool

    init(kind: Kind, title: String, detail: String, blocksImport: Bool = false) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.blocksImport = blocksImport
    }
}

struct AirstripRunCheck: Identifiable {
    let id = UUID()
    let url: URL
    let results: [FolderCheckResult]
    let guideMarkdown: String

    var canImport: Bool {
        !results.contains(where: \.blocksImport)
    }

    var verdict: FolderCheckResult.Kind {
        if results.contains(where: { $0.blocksImport }) { return .fail }
        if results.contains(where: { $0.kind == .fail || $0.kind == .warn }) { return .warn }
        return .pass
    }

    var verdictTitle: String {
        switch verdict {
        case .pass: return "Ready to add"
        case .warn: return "Can add after setup"
        case .fail: return "Needs project preparation"
        case .info: return "Checked"
        }
    }
}

/// Static analysis of a folder: manifest, run command, Python needs,
/// declared tools, and Ollama models — the same rules the launcher applies.
enum FolderCheck {
    static func analyze(url: URL, python: DependencyStatus, node: DependencyStatus, ollama: DependencyStatus) async -> AirstripRunCheck {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            let results = [
                FolderCheckResult(
                    kind: .fail,
                    title: "Item does not exist",
                    detail: "Airstrip could not read this dropped item.",
                    blocksImport: true
                )
            ]
            return AirstripRunCheck(url: url, results: results, guideMarkdown: guideMarkdown(for: url, results: results))
        }

        let results: [FolderCheckResult]
        if isDirectory.boolValue {
            results = await analyze(folder: url, python: python, node: node, ollama: ollama)
        } else {
            results = analyze(file: url, python: python, node: node)
        }

        return AirstripRunCheck(url: url, results: results, guideMarkdown: guideMarkdown(for: url, results: results))
    }

    static func analyze(folder: URL, python: DependencyStatus, node: DependencyStatus, ollama: DependencyStatus) async -> [FolderCheckResult] {
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
                    detail: error.localizedDescription,
                    blocksImport: true
                ))
            }
        } else {
            let hints = entryPointHints(in: folder)
            if hints.isEmpty {
                results.append(.init(
                    kind: .fail,
                    title: "No airstrip.json and no recognizable entry point",
                    detail: "Add an airstrip.json with a run command, or include app.py / main.py.",
                    blocksImport: true
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
                    detail: "Add a \"run\" field or an \"actions\" array to airstrip.json.",
                    blocksImport: true
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
                        detail: "The manifest points to a requirements file that is not in the folder.",
                        blocksImport: true
                    ))
                }
            }
        }

        // Node runtime.
        let packageJSONExists = fm.fileExists(atPath: folder.appendingPathComponent("package.json").path)
        let needsNode = packageJSONExists || manifestNeedsNode(manifest)
        if needsNode {
            switch node {
            case .available(let version):
                results.append(.init(kind: .pass, title: "Node/npm is installed", detail: version))
            case .missing:
                results.append(.init(
                    kind: .fail,
                    title: "Needs Node/npm, which is not installed",
                    detail: "Install Node from the Runtime panel before running this web app."
                ))
            case .unknown:
                results.append(.init(kind: .info, title: "Node/npm status still being checked", detail: ""))
            }

            if packageJSONExists {
                results.append(packageJSONSummary(folder: folder))
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
        for candidate in ["app.py", "main.py", "app/main.py", "streamlit_app.py", "README.md", "package.json", "index.html"] {
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

    private static func manifestNeedsNode(_ manifest: ProjectManifest?) -> Bool {
        guard let manifest else { return false }
        let commands = [manifest.run ?? ""] + (manifest.actions ?? []).map(\.command)
        return commands.contains { command in
            ["npm ", "npx ", "node ", "pnpm ", "yarn "].contains { command.contains($0) || command.hasPrefix($0) }
        }
    }

    private static func packageJSONSummary(folder: URL) -> FolderCheckResult {
        let url = folder.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: url),
              let package = try? JSONDecoder().decode(NodePackageManifest.self, from: data) else {
            return .init(
                kind: .fail,
                title: "package.json could not be read",
                detail: "Fix package.json syntax, then try again.",
                blocksImport: true
            )
        }

        guard let scripts = package.scripts, !scripts.isEmpty else {
            return .init(
                kind: .fail,
                title: "package.json has no scripts",
                detail: "Add a dev/start script or an airstrip.json run command.",
                blocksImport: true
            )
        }

        let runnable = ["dev", "start", "preview"].filter { scripts[$0] != nil }
        if runnable.isEmpty {
            return .init(
                kind: .fail,
                title: "package.json has scripts, but no dev/start script",
                detail: "Add an airstrip.json action for the exact command Airstrip should run.",
                blocksImport: true
            )
        }

        return .init(
            kind: .pass,
            title: "Web app scripts found",
            detail: "Airstrip can infer: \(runnable.map { "npm run \($0)" }.joined(separator: ", "))."
        )
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

    private static func analyze(file: URL, python: DependencyStatus, node: DependencyStatus) -> [FolderCheckResult] {
        let ext = file.pathExtension.lowercased()
        switch ext {
        case "py":
            var results = [
                FolderCheckResult(kind: .pass, title: "Python script", detail: "Airstrip will wrap this file in a small runnable app folder.")
            ]
            appendPythonStatus(python, to: &results)
            return results
        case "html", "htm":
            var results = [
                FolderCheckResult(kind: .pass, title: "Static web page", detail: "Airstrip will serve it locally and open it in a web tab.")
            ]
            appendPythonStatus(python, to: &results)
            return results
        case "js", "jsx", "ts", "tsx":
            var results = [
                FolderCheckResult(kind: .pass, title: "Frontend source file", detail: "Airstrip will create a minimal Vite wrapper around this file.")
            ]
            appendNodeStatus(node, to: &results)
            return results
        default:
            return [
                FolderCheckResult(
                    kind: .fail,
                    title: "Unsupported file type",
                    detail: "Drop a project folder, a Python script, an HTML file, or a JS/TS/React file.",
                    blocksImport: true
                )
            ]
        }
    }

    private static func appendPythonStatus(_ python: DependencyStatus, to results: inout [FolderCheckResult]) {
        switch python {
        case .available(let version):
            results.append(.init(kind: .pass, title: "Python is installed", detail: version))
        case .missing:
            results.append(.init(kind: .warn, title: "Python needs installing", detail: "Use the Runtime panel in Airstrip. The project can be added now."))
        case .unknown:
            results.append(.init(kind: .info, title: "Python status still being checked", detail: ""))
        }
    }

    private static func appendNodeStatus(_ node: DependencyStatus, to results: inout [FolderCheckResult]) {
        switch node {
        case .available(let version):
            results.append(.init(kind: .pass, title: "Node/npm is installed", detail: version))
        case .missing:
            results.append(.init(kind: .warn, title: "Node/npm needs installing", detail: "Use the Runtime panel in Airstrip. The project can be added now."))
        case .unknown:
            results.append(.init(kind: .info, title: "Node/npm status still being checked", detail: ""))
        }
    }

    private static func guideMarkdown(for url: URL, results: [FolderCheckResult]) -> String {
        let blocking = results.filter(\.blocksImport)
        let findings = results.map { "- \($0.title)\($0.detail.isEmpty ? "" : ": \($0.detail)")" }.joined(separator: "\n")
        let action = blocking.isEmpty
            ? "This item is close. Keep the app behavior the same, but make the project explicit and easy for Airstrip to run."
            : "This item is not Airstrip-ready yet. Please prepare it so a non-technical user can drop it into Airstrip and run it."

        return """
        # Make this project Airstrip-ready

        Project path:
        `\(url.path)`

        \(action)

        ## Airstrip run-checker findings
        \(findings)

        ## Required outcome
        1. Add or fix `airstrip.json` at the project root.
        2. Keep all commands local and non-destructive.
        3. If this is a web app, make it read `PORT` or use `{PORT}` in `airstrip.json`.
        4. If this is Python, add `requirements.txt` for packages Airstrip should install.
        5. If it needs system tools, declare them under `tools` with a Homebrew package when possible.

        ## Good `airstrip.json` templates

        Python script:
        ```json
        {
          "name": "My Automation",
          "run": "python app.py",
          "requirements": "requirements.txt"
        }
        ```

        Local web app:
        ```json
        {
          "name": "My Web App",
          "actions": [
            {
              "name": "Start",
              "command": "python app.py --port {PORT}",
              "isDefault": true,
              "web": {
                "port": 8000,
                "openPath": "/",
                "openOnStart": true,
                "allowPortFallback": true
              }
            }
          ]
        }
        ```

        Node web app:
        ```json
        {
          "name": "My Node App",
          "tools": [{ "command": "npm", "brew": "node" }],
          "actions": [
            {
              "name": "Start",
              "command": "if [ ! -d node_modules ]; then npm install; fi && npm run dev -- --host 127.0.0.1 --port {PORT}",
              "isDefault": true,
              "web": {
                "port": 5173,
                "openPath": "/",
                "openOnStart": true,
                "allowPortFallback": true
              }
            }
          ]
        }
        ```
        """
    }
}

private struct NodePackageManifest: Decodable {
    var scripts: [String: String]?
}
