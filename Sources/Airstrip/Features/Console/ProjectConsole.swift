import AppKit
import SwiftUI
import WebKit

// MARK: - App page (full-width tab content)

/// Full tab content for a project: header with controls, action sidebar,
/// and a large output console.
struct ProjectPage: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    let project: AirstripProject
    let openWebTab: () -> Void
    let openAIStudio: () -> Void

    private var state: ProjectRuntimeState {
        store.runtimeStates[project.id] ?? ProjectRuntimeState()
    }

    private var status: ProjectDisplayStatus {
        ProjectDisplayStatus(state)
    }

    private var actions: [ProjectAction] {
        store.actions(for: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.vertical, 14)

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    sidePanel
                        .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)

                    Divider()

                    OutputConsole(project: project, state: state, openAIStudio: openAIStudio)
                        .padding(16)
                }

                VStack(spacing: 0) {
                    sidePanel
                        .frame(maxHeight: 230)

                    Divider()

                    OutputConsole(project: project, state: state, openAIStudio: openAIStudio)
                        .padding(16)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !state.missingTools.isEmpty {
                    MissingToolsCard(project: project, tools: state.missingTools)
                }

                if actions.count > 1 {
                    actionSection
                }

                notesSection

                infoSection
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ProjectIconBadge(project: project, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                statusLine
            }

            Spacer()

            if state.isRunning, state.activeWebURL != nil {
                Button {
                    openWebTab()
                } label: {
                    Label("Open Web UI", systemImage: "macwindow")
                }
                .airstripGlassButton()
                .controlSize(.large)
                .noFocusRing()
            }

            Button {
                store.toggle(project)
            } label: {
                Label(
                    state.isPreparing ? "Checking..." : (state.isRunning ? "Stop" : "Run"),
                    systemImage: state.isRunning ? "stop.fill" : "play.fill"
                )
                .frame(minWidth: 70)
            }
            .airstripGlassButton(prominent: true)
            .controlSize(.large)
            .tint(state.isRunning ? .red : .accentColor)
            .disabled(state.isPreparing)
            .noFocusRing()
        }
    }

    private var statusLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText(now: context.date))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    private func statusText(now: Date) -> String {
        switch status {
        case .running:
            var text = state.activeActionName ?? "Running"
            if let port = state.activeWebPort {
                text += " · localhost:\(port)"
            }
            if let startedAt = state.startedAt {
                text += " · \(elapsedString(from: startedAt, to: now))"
            }
            return text
        case .preparing:
            return "Checking requirements..."
        case .finished:
            return "Finished"
        case .needsAttention(let code):
            return "Needs attention (code \(code))"
        case .idle:
            return "Ready to run"
        }
    }

    private func elapsedString(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var statusColor: Color {
        switch status {
        case .running: return .green
        case .preparing: return .yellow
        case .finished: return .green
        case .needsAttention: return .orange
        case .idle: return .secondary.opacity(0.5)
        }
    }

    // MARK: Sections

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Actions")

            VStack(spacing: 1) {
                ForEach(actions) { action in
                    ActionRow(action: action, isDisabled: state.isRunning || state.isPreparing) {
                        store.run(project, action: action)
                    }
                }
            }
            .airstripGlassPanel(cornerRadius: 10, fallbackOpacity: 0.35)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Notes")

            TextEditor(text: Binding(
                get: { project.notes ?? "" },
                set: { store.updateNotes(project, notes: $0) }
            ))
            .font(.system(size: 12))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 84, maxHeight: 160)
            .airstripGlassPanel(cornerRadius: 10, fallbackOpacity: 0.35)
            .overlay(alignment: .topLeading) {
                if (project.notes ?? "").isEmpty {
                    Text("Anything to remember about this app...")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Project")

            VStack(alignment: .leading, spacing: 10) {
                Text(project.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                HStack {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([project.path])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        store.remove(project)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
            }
            .padding(12)
            .airstripGlassPanel(cornerRadius: 10, fallbackOpacity: 0.35)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Action row

private struct ActionRow: View {
    let action: ProjectAction
    let isDisabled: Bool
    let run: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: action.web != nil ? "globe" : "terminal")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            Text(action.name)
                .font(.system(size: 13))
                .lineLimit(1)

            if action.isDefault {
                Text("Default")
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            Spacer()

            Button(action: run) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(isDisabled ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .opacity(isHovering || isDisabled ? 1 : 0.45)
            .noFocusRing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Output console

private struct OutputConsole: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var ollama: OllamaManager
    let project: AirstripProject
    let state: ProjectRuntimeState
    let openAIStudio: () -> Void

    /// User-toggled expansion overrides; by default only the latest run is open.
    @State private var expansionOverrides: [UUID: Bool] = [:]
    @State private var showErrorFixSelector = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if state.detectedIssue != nil {
                    Button {
                        store.refreshActivePorts()
                        ollama.refreshServerStatus()
                        showErrorFixSelector = true
            } label: {
                        Label("Fix Error", systemImage: "stethoscope")
                    }
                    .airstripGlassButton(prominent: true)
                    .controlSize(.small)
                    .tint(.orange)
                    .noFocusRing()
                    .help("Diagnose the port conflict and choose a local fix")
                }

                if !state.runs.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.combinedLog, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy output")
                    .noFocusRing()

                    Button {
                        store.clearLog(for: project)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear output")
                    .disabled(state.isRunning)
                    .noFocusRing()
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .sheet(isPresented: $showErrorFixSelector) {
                if let issue = state.detectedIssue {
                    ErrorFixSelectorSheet(
                        project: project,
                        issue: issue,
                        openAIStudio: openAIStudio,
                        dismiss: { showErrorFixSelector = false }
                    )
                    .frame(width: 460)
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if state.runs.isEmpty {
                            Text("Output appears here when the project runs.")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(4)
                        } else {
                            ForEach(state.runs) { run in
                                RunSection(
                                    run: run,
                                    isExpanded: isExpanded(run),
                                    toggle: { expansionOverrides[run.id] = !isExpanded(run) }
                                )
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Color.clear
                        .frame(height: 1)
                        .id("console-bottom")
                }
                .onChange(of: state.runs) { _ in
                    proxy.scrollTo("console-bottom", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("console-bottom", anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .airstripGlassPanel(cornerRadius: 12, fallbackOpacity: 0.45)
        }
    }

    private func isExpanded(_ run: RunRecord) -> Bool {
        expansionOverrides[run.id] ?? (run.id == state.runs.last?.id)
    }
}

private struct ErrorFixSelectorSheet: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var ollama: OllamaManager
    let project: AirstripProject
    let issue: RuntimeIssue
    let openAIStudio: () -> Void
    let dismiss: () -> Void
    @State private var showAIOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Fix Error")
                        .font(.headline)
                    Text(issue.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .noFocusRing()
            }

            issueSummary

            localFixes

            Divider()

            Button {
                showAIOptions.toggle()
            } label: {
                HStack {
                    Label("Use AI if this does not work", systemImage: "sparkles")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showAIOptions ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .noFocusRing()

            if showAIOptions {
                aiOptions
            }
        }
        .padding(18)
        .onAppear {
            store.refreshActivePorts()
            ollama.refreshServerStatus()
        }
    }

    private var localFixes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try Airstrip Fix")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                if let port = issue.port {
                    Text("Airstrip saw the app try to use port \(port). \(portOwnerText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if issue.port != nil {
                        Button {
                            store.terminateConflictingPortAndRetry(project, issue: issue)
                            dismiss()
                        } label: {
                            Label("Kill Port & Retry", systemImage: "xmark.octagon")
                        }
                        .airstripGlassButton(prominent: true)
                        .controlSize(.small)
                        .tint(.red)
                        .noFocusRing()
                    }

                    if issue.suggestedPort != nil {
                        Button {
                            store.retryWithSuggestedPort(project, issue: issue)
                            dismiss()
                        } label: {
                            Label("Use Suggested Port", systemImage: "arrow.triangle.branch")
                        }
                        .airstripGlassButton(prominent: true)
                        .controlSize(.small)
                        .tint(.accentColor)
                        .noFocusRing()
                    }

                    Button {
                        dismiss()
                    } label: {
                        Label("Stop Trying", systemImage: "pause.circle")
                    }
                    .airstripGlassButton()
                    .controlSize(.small)
                    .noFocusRing()
                }
            }
            .padding(12)
            .airstripGlassPanel(cornerRadius: 10, fallbackOpacity: 0.35)
        }
    }

    private var aiOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose AI")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

            if ollama.availableTargets.isEmpty {
                Text("Add an API key or start Ollama with a local model to use AI repair.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(ollama.availableTargets) { target in
                    Button {
                        ask(target)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: target.provider.iconName)
                                .frame(width: 18)
                                .foregroundStyle(target.provider.brandColor)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(target.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                if let size = target.sizeLabel {
                                    Text(size)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!ollama.canUseTarget(target.id))
                    .airstripGlassPanel(cornerRadius: 8, tint: target.provider.brandColor, interactive: true, fallbackOpacity: 0.35)
                    .noFocusRing()
                }
            }
        }
    }

    private var issueSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                if let port = issue.port {
                    Label(":\(port)", systemImage: "network")
                }
                if let suggestedPort = issue.suggestedPort {
                    Label("Try :\(suggestedPort)", systemImage: "arrow.triangle.branch")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .airstripGlassPanel(cornerRadius: 10, tint: .orange, fallbackOpacity: 0.35)
    }

    private var portOwnerText: String {
        guard let port = issue.port else { return "" }
        guard let info = store.activePorts.first(where: { $0.port == port }) else {
            return "No current listener showed up in the latest port scan; the process may have exited already."
        }

        var parts: [String] = []
        if let processName = info.processName {
            parts.append("\(processName)")
        } else {
            parts.append("A process")
        }
        if let pid = info.pid {
            parts.append("pid \(pid)")
        }
        if info.isAirstripProject, let name = info.airstripProjectName {
            parts.append("from \(name)")
        }
        return "\(parts.joined(separator: ", ")) is listening there."
    }

    private func ask(_ target: AIChatTarget) {
        let prompt = store.errorFixPrompt(for: project, issue: issue, target: target)
        ollama.selectedModels = [target.id]
        ollama.send(prompt)
        dismiss()
        openAIStudio()
    }
}

/// One run of an action: colored status header plus collapsible full output.
private struct RunSection: View {
    let run: RunRecord
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)

                    statusIcon

                    Text(run.actionName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(headerColor)

                    Text(headerDetail)
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noFocusRing()

            if isExpanded {
                Text(run.output.isEmpty ? (run.isOpen ? "Starting..." : "No output.") : run.output)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(run.output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .airstripGlassPanel(cornerRadius: 8, tint: headerColor, interactive: true, fallbackOpacity: 0.35)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if run.isOpen {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.6)
                .frame(width: 12, height: 12)
        } else if run.exitCode == 0 {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        } else {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        }
    }

    private var headerColor: Color {
        if run.isOpen { return .blue }
        return run.exitCode == 0 ? .green : .orange
    }

    private var headerDetail: String {
        var parts = [run.startedAt.formatted(date: .omitted, time: .shortened)]
        if let endedAt = run.endedAt {
            let seconds = max(0, Int(endedAt.timeIntervalSince(run.startedAt)))
            parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        if let exitCode = run.exitCode, exitCode != 0 {
            parts.append("code \(exitCode)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Missing tools

private struct MissingToolsCard: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    let project: AirstripProject
    let tools: [ProjectTool]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text("Almost there")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    store.dismissMissingTools(for: project)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .noFocusRing()
            }

            Text("This project needs \(tools.map(\.command).joined(separator: ", ")) before it can run. Click install — a Terminal window will do the work for you.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                ForEach(tools) { tool in
                    if let package = tool.brew {
                        Button("Install \(tool.command)") {
                            dependencyManager.installBrewPackage(package)
                        }
                        .airstripGlassButton(prominent: true)
                        .controlSize(.small)
                        .tint(.orange)
                        .noFocusRing()
                    }
                }
            }
        }
        .padding(14)
        .airstripGlassPanel(cornerRadius: 10, tint: .orange, fallbackOpacity: 0.5)
    }
}

// MARK: - Web page (embedded browser tab)

/// Embedded browser tab for a project's local web UI.
struct WebPage: View {
    @EnvironmentObject private var store: ProjectStore
    let project: AirstripProject
    let url: URL

    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    reloadToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .noFocusRing()
                .help("Reload")

                Text(url.absoluteString)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 420)
                    .airstripGlassCapsule(interactive: true)

                Spacer()

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .noFocusRing()

                Button(role: .destructive) {
                    store.stop(project)
                } label: {
                    Label("Stop Server", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
                .noFocusRing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            Divider()

            WebView(url: url, reloadToken: reloadToken)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// WKWebView wrapper that retries while the local server is still warming up.
private struct WebView: NSViewRepresentable {
    @EnvironmentObject private var store: ProjectStore
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, store: store)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        context.coordinator.lastReloadToken = reloadToken
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            context.coordinator.retriesLeft = 5
            webView.load(URLRequest(url: url))
        } else if context.coordinator.lastReloadToken != reloadToken {
            context.coordinator.lastReloadToken = reloadToken
            webView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        var url: URL
        let store: ProjectStore
        var lastReloadToken = 0
        var retriesLeft = 5
        private var activeDownloads: [WKDownload: (UUID, NSKeyValueObservation, URL)] = [:]

        init(url: URL, store: ProjectStore) {
            self.url = url
            self.store = store
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        // MARK: - WKDownloadDelegate

        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let savePanel = NSSavePanel()
            savePanel.nameFieldStringValue = suggestedFilename
            savePanel.canCreateDirectories = true
            
            savePanel.begin { [weak self] panelResponse in
                guard let self else {
                    completionHandler(nil)
                    return
                }
                
                if panelResponse == .OK, let url = savePanel.url {
                    let downloadID = UUID()
                    
                    self.store.addDownload(id: downloadID, filename: suggestedFilename, targetURL: url)
                    
                    let observation = download.progress.observe(\.fractionCompleted) { [weak self] progressObj, _ in
                        guard let self else { return }
                        let fraction = progressObj.fractionCompleted
                        DispatchQueue.main.async {
                            self.store.updateDownloadProgress(id: downloadID, progress: fraction)
                        }
                    }
                    
                    self.activeDownloads[download] = (downloadID, observation, url)
                    completionHandler(url)
                } else {
                    completionHandler(nil)
                }
            }
        }

        func downloadDidFinish(_ download: WKDownload) {
            if let (downloadID, observation, _) = activeDownloads[download] {
                observation.invalidate()
                store.completeDownload(id: downloadID)
                activeDownloads.removeValue(forKey: download)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            if let (downloadID, observation, _) = activeDownloads[download] {
                observation.invalidate()
                store.failDownload(id: downloadID, errorDescription: error.localizedDescription)
                activeDownloads.removeValue(forKey: download)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // The server may not be accepting connections yet right after
            // launch; retry a few times before giving up.
            guard retriesLeft > 0 else { return }
            retriesLeft -= 1
            let url = url
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak webView] in
                webView?.load(URLRequest(url: url))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retriesLeft = 5
        }
    }
}
