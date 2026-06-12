import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @State private var openTabs: [WorkspaceTab] = []
    @State private var activeTab: WorkspaceTab = .springboard
    @State private var isDropTargeted = false

    private var allTabs: [WorkspaceTab] {
        [.springboard] + openTabs
    }

    private var runningProjects: [AirstripProject] {
        store.projects.filter { project in
            let state = store.runtimeStates[project.id]
            return state?.isRunning == true || state?.isPreparing == true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WorkspaceTabStrip(
                    tabs: allTabs,
                    activeTab: activeTab,
                    onSelect: { activeTab = $0 },
                    onClose: closeTab
                )

                Divider()

                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !runningProjects.isEmpty {
                            RunningStrip(
                                projects: runningProjects,
                                focusApp: { openApp($0) },
                                focusWeb: { openWeb($0) }
                            )
                        }
                    }
            }
            .navigationTitle("Airstrip")
            .toolbar {
                // All window actions live on the right side of the bar.
                ToolbarItemGroup(placement: .primaryAction) {
                    RuntimeHealthButton()

                    Button {
                        store.refreshProjectsFromDisk()
                    } label: {
                        Label("Rescan Folder", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .help("Re-scan the projects folder: picks up apps that were added or removed in Finder")

                    Button {
                        store.revealAirstripFolder()
                    } label: {
                        Label("Open Projects Folder", systemImage: "folder")
                    }
                    .help("Show the Airstrip projects folder in Finder")

                    Button {
                        store.importWithPanel()
                    } label: {
                        Label("Import Project", systemImage: "plus")
                    }
                    .help("Import an automation folder")
                }
            }
        }
        .onChange(of: store.projects) { projects in
            openTabs.removeAll { tab in
                guard let id = tab.projectID else { return false }
                return !projects.contains(where: { $0.id == id })
            }
            ensureActiveTabExists()
        }
        .onChange(of: store.runtimeStates) { states in
            // Web tabs only make sense while their server is up.
            openTabs.removeAll { tab in
                guard tab.isWeb, let id = tab.projectID else { return false }
                let state = states[id]
                return state?.isRunning != true || state?.activeWebURL == nil
            }
            ensureActiveTabExists()

            // If the user is already looking at the app when it finishes,
            // that counts as having checked the result.
            if case .app(let id) = activeTab, states[id]?.acknowledged == false {
                store.acknowledge(id)
            }
        }
        .onChange(of: store.pendingWebFocus) { id in
            guard let id else { return }
            store.pendingWebFocus = nil
            openWeb(id)
        }
        .overlay {
            if isDropTargeted {
                DropTargetOverlay()
            }
        }
        .onDrop(of: [.folder, .fileURL], isTargeted: $isDropTargeted) { providers in
            store.importFromDrop(providers: providers)
        }
        .alert(
            "Airstrip",
            isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) { store.lastError = nil }
            },
            message: {
                Text(store.lastError ?? "")
            }
        )
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .springboard:
            ZStack {
                LauncherGrid(openProject: openApp)

                if store.projects.isEmpty {
                    EmptyDropView()
                }
            }
            .background(Color(nsColor: .underPageBackgroundColor))

        case .app(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectPage(project: project) {
                    openWeb(id)
                }
            }

        case .web(let id):
            if let project = store.projects.first(where: { $0.id == id }),
               let url = store.runtimeStates[id]?.activeWebURL {
                WebPage(project: project, url: url)
            }
        }
    }

    // MARK: Tab management

    private func openApp(_ id: AirstripProject.ID) {
        if !openTabs.contains(.app(id)) {
            openTabs.append(.app(id))
        }
        activeTab = .app(id)
        store.acknowledge(id)
    }

    private func openWeb(_ id: AirstripProject.ID) {
        guard store.runtimeStates[id]?.activeWebURL != nil else {
            openApp(id)
            return
        }
        if !openTabs.contains(.app(id)) {
            openTabs.append(.app(id))
        }
        if !openTabs.contains(.web(id)) {
            // Keep the web tab glued to its app tab so they read as a group.
            if let appIndex = openTabs.firstIndex(of: .app(id)) {
                openTabs.insert(.web(id), at: appIndex + 1)
            } else {
                openTabs.append(.web(id))
            }
        }
        activeTab = .web(id)
    }

    private func closeTab(_ tab: WorkspaceTab) {
        switch tab {
        case .springboard:
            return
        case .app(let id):
            // Closing an app tab closes its grouped web tab too. The project
            // itself keeps running; the Running strip still shows it.
            openTabs.removeAll { $0.projectID == id }
        case .web:
            openTabs.removeAll { $0 == tab }
        }
        ensureActiveTabExists()
    }

    private func ensureActiveTabExists() {
        if !allTabs.contains(activeTab) {
            if let projectID = activeTab.projectID, openTabs.contains(.app(projectID)) {
                activeTab = .app(projectID)
            } else {
                activeTab = openTabs.last ?? .springboard
            }
        }
    }
}

// MARK: - Tab strip

/// Browser-style top-level tab strip. The springboard is pinned on the left;
/// a project's app tab and web tab render as one visual group.
private struct WorkspaceTabStrip: View {
    @EnvironmentObject private var store: ProjectStore
    let tabs: [WorkspaceTab]
    let activeTab: WorkspaceTab
    let onSelect: (WorkspaceTab) -> Void
    let onClose: (WorkspaceTab) -> Void

    private struct TabGroup: Identifiable {
        let id: String
        let tabs: [WorkspaceTab]
        let projectID: AirstripProject.ID?
    }

    private var groups: [TabGroup] {
        var result: [TabGroup] = []
        for tab in tabs {
            if let projectID = tab.projectID,
               let last = result.last,
               last.projectID == projectID {
                result[result.count - 1] = TabGroup(
                    id: last.id,
                    tabs: last.tabs + [tab],
                    projectID: projectID
                )
            } else {
                result.append(TabGroup(id: tab.id, tabs: [tab], projectID: tab.projectID))
            }
        }
        return result
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(groups) { group in
                    groupView(group)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func groupView(_ group: TabGroup) -> some View {
        if group.tabs.count > 1, let projectID = group.projectID {
            let tint = store.projects.first(where: { $0.id == projectID })
                .map { ProjectTint.color(for: $0.name) } ?? .accentColor

            HStack(spacing: 2) {
                ForEach(group.tabs) { tab in
                    tabChip(tab)
                }
            }
            .padding(2)
            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(tint.opacity(0.25), lineWidth: 1)
            }
        } else if let tab = group.tabs.first {
            tabChip(tab)
        }
    }

    @ViewBuilder
    private func tabChip(_ tab: WorkspaceTab) -> some View {
        switch tab {
        case .springboard:
            SpringboardTabChip(isActive: activeTab == tab) {
                onSelect(tab)
            }
        case .app(let id), .web(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectTabChip(
                    project: project,
                    tab: tab,
                    isActive: activeTab == tab,
                    isRunning: store.runtimeStates[id]?.isRunning == true,
                    select: { onSelect(tab) },
                    close: { onClose(tab) }
                )
            }
        }
    }
}

private struct SpringboardTabChip: View {
    let isActive: Bool
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

            Text("Springboard")
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(chipBackground(isActive: isActive, isHovering: isHovering))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}

private struct ProjectTabChip: View {
    let project: AirstripProject
    let tab: WorkspaceTab
    let isActive: Bool
    let isRunning: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if tab.isWeb {
                Image(systemName: "globe")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isActive ? ProjectTint.color(for: project.name) : .secondary)
            } else {
                ProjectIconBadge(project: project, size: 15)
            }

            Text(tab.isWeb ? "Web UI" : project.name)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            if isRunning, !tab.isWeb {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering || isActive ? 1 : 0)
            .help("Close tab")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(chipBackground(isActive: isActive, isHovering: isHovering))
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
    }
}

private func chipBackground(isActive: Bool, isHovering: Bool) -> some View {
    RoundedRectangle(cornerRadius: 8)
        .fill(
            isActive
                ? Color(nsColor: .windowBackgroundColor)
                : (isHovering ? Color.primary.opacity(0.05) : Color.clear)
        )
        .shadow(color: isActive ? .black.opacity(0.12) : .clear, radius: 2, y: 1)
}

// MARK: - Running strip

/// Always-visible bar listing everything that is currently running, with
/// ports, elapsed time, and stop buttons.
private struct RunningStrip: View {
    @EnvironmentObject private var store: ProjectStore
    let projects: [AirstripProject]
    let focusApp: (AirstripProject.ID) -> Void
    let focusWeb: (AirstripProject.ID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Label("Running", systemImage: "bolt.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)

                    ForEach(projects) { project in
                        RunningChip(
                            project: project,
                            focus: { focusApp(project.id) },
                            focusWeb: { focusWeb(project.id) }
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
        }
        .background(.bar)
    }
}

private struct RunningChip: View {
    @EnvironmentObject private var store: ProjectStore
    let project: AirstripProject
    let focus: () -> Void
    let focusWeb: () -> Void

    private var state: ProjectRuntimeState {
        store.runtimeStates[project.id] ?? ProjectRuntimeState()
    }

    var body: some View {
        HStack(spacing: 8) {
            PulsingDot(color: state.isPreparing ? .yellow : .green)
                .scaleEffect(0.8)

            VStack(alignment: .leading, spacing: 0) {
                Text(project.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(detailText(now: context.date))
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if state.isRunning, state.activeWebURL != nil {
                Button(action: focusWeb) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Open web tab")
            }

            Button {
                store.stop(project)
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .frame(width: 16, height: 16)
                    .background(.red.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!state.isRunning)
            .help("Stop \(project.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
        .help("Show \(project.name) details")
    }

    private func detailText(now: Date) -> String {
        var parts: [String] = []
        if let action = state.activeActionName {
            parts.append(action)
        }
        if let port = state.activeWebPort {
            parts.append(":\(port)")
        }
        if let startedAt = state.startedAt {
            let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
            parts.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        return parts.isEmpty ? "Starting..." : parts.joined(separator: " · ")
    }
}

// MARK: - Runtime health

private struct RuntimeHealthButton: View {
    @EnvironmentObject private var dependencyManager: DependencyManager
    @State private var showPopover = false

    private var anyMissing: Bool {
        [dependencyManager.python, dependencyManager.homebrew, dependencyManager.ollama]
            .contains(.missing)
    }

    private var anyChecking: Bool {
        [dependencyManager.python, dependencyManager.homebrew, dependencyManager.ollama]
            .contains(.unknown)
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Label("Runtime", systemImage: symbolName)
                .foregroundStyle(symbolColor)
        }
        .help("Python, Homebrew, and Ollama status")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            RuntimeHealthPopover()
        }
    }

    private var symbolName: String {
        if anyChecking { return "circle.dotted" }
        return anyMissing ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
    }

    private var symbolColor: Color {
        if anyChecking { return .secondary }
        return anyMissing ? .orange : .green
    }
}

private struct RuntimeHealthPopover: View {
    @EnvironmentObject private var dependencyManager: DependencyManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Runtime")
                    .font(.headline)

                Spacer()

                Button {
                    dependencyManager.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Check again")
            }

            RuntimeRow(
                name: "Python",
                detail: "Runs automation scripts",
                status: dependencyManager.python,
                install: dependencyManager.installPython
            )

            RuntimeRow(
                name: "Homebrew",
                detail: "Installs missing tools",
                status: dependencyManager.homebrew,
                install: dependencyManager.installHomebrew
            )

            RuntimeRow(
                name: "Ollama",
                detail: "Runs local AI models",
                status: dependencyManager.ollama,
                install: dependencyManager.installOllama
            )
        }
        .padding(16)
        .frame(width: 300)
    }
}

private struct RuntimeRow: View {
    let name: String
    let detail: String
    let status: DependencyStatus
    let install: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 12, weight: .medium))

                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if status == .missing {
                Button("Install", action: install)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var subtitle: String {
        switch status {
        case .unknown:
            return "Checking..."
        case .available(let version):
            return version
        case .missing:
            return detail
        }
    }

    private var color: Color {
        switch status {
        case .unknown: return .yellow
        case .available: return .green
        case .missing: return .orange
        }
    }
}

// MARK: - Empty + drop states

private struct EmptyDropView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .foregroundStyle(.quaternary)
                    .frame(width: 110, height: 110)

                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text("Drop an automation folder here")
                    .font(.title3.weight(.semibold))

                Text("It becomes an app icon you can run with one click.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                store.importWithPanel()
            } label: {
                Label("Choose Folder...", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)

            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [12, 8]))
                .padding(14)

            VStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 40))

                Text("Drop to add")
                    .font(.title3.weight(.semibold))
            }
            .foregroundStyle(Color.accentColor)
        }
        .allowsHitTesting(false)
    }
}
