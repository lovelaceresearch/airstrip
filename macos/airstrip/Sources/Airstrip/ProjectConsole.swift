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

            HStack(spacing: 0) {
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
                }
                .frame(width: 290)

                Divider()

                OutputConsole(project: project, state: state)
                    .padding(16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                .buttonStyle(.bordered)
                .controlSize(.large)
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(state.isRunning ? .red : .accentColor)
            .disabled(state.isPreparing)
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
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
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
    let project: AirstripProject
    let state: ProjectRuntimeState

    /// User-toggled expansion overrides; by default only the latest run is open.
    @State private var expansionOverrides: [UUID: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Output")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if !state.runs.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.combinedLog, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy output")

                    Button {
                        store.clearLog(for: project)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear output")
                    .disabled(state.isRunning)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

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
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 1)
            }
        }
    }

    private func isExpanded(_ run: RunRecord) -> Bool {
        expansionOverrides[run.id] ?? (run.id == state.runs.last?.id)
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
        .background(headerColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(headerColor.opacity(0.18), lineWidth: 1)
        }
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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        }
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
                .help("Reload")

                Text(url.absoluteString)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: 420)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                Spacer()

                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Safari", systemImage: "safari")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button(role: .destructive) {
                    store.stop(project)
                } label: {
                    Label("Stop Server", systemImage: "stop.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.red)
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
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
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

    final class Coordinator: NSObject, WKNavigationDelegate {
        var url: URL
        var lastReloadToken = 0
        var retriesLeft = 5

        init(url: URL) {
            self.url = url
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
