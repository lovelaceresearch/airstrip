import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @State private var openTabs: [WorkspaceTab] = []
    @State private var activeTab: WorkspaceTab = .springboard
    @State private var isDropTargeted = false
    @State private var searchText = ""
    @State private var libraryFilter: ProjectLibraryFilter = .all
    @State private var isSearchExpanded = false
    @State private var showOnboarding = false
    @State private var isRunningDropCheck = false
    @State private var dropCheckResults: [AirstripRunCheck] = []
    @State private var pendingDropURLs: [URL] = []
    @State private var dropCheckTask: Task<Void, Never>?
    @AppStorage("hasSeenAirstripOnboarding") private var hasSeenOnboarding = false

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
        appShell
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
        .onChange(of: store.pendingImportPanelRequest) { request in
            guard request != nil else { return }
            store.pendingImportPanelRequest = nil
            openImportPanelForRunCheck()
        }
        // Folders added or removed in Finder show up whenever the user comes
        // back to Airstrip; no manual refresh button needed.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshProjectsFromDisk()
        }
        .overlay {
            if isDropTargeted {
                DropTargetOverlay()
            }
        }
        .onDrop(of: [.folder, .fileURL], isTargeted: $isDropTargeted) { providers in
            runCheckForDroppedItems(providers)
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
        .sheet(isPresented: $showOnboarding) {
            FirstRunOnboardingSheet(hasSeenOnboarding: $hasSeenOnboarding)
        }
        .sheet(isPresented: Binding(
            get: { isRunningDropCheck || !dropCheckResults.isEmpty },
            set: { visible in
                if !visible {
                    isRunningDropCheck = false
                    dropCheckResults = []
                }
            }
        )) {
            ImportRunCheckerSheet(isChecking: isRunningDropCheck, checks: dropCheckResults)
                .environmentObject(store)
        }
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
    }

    private var appShell: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if store.isSidebarOpen {
                    StatusSidebar()
                        .frame(width: 300)
                        .transition(.move(edge: .leading))
                }

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
            .toolbar(id: "main-toolbar") {
                if #available(macOS 26.0, *) {
                    ToolbarItem(id: "navigation", placement: .navigation) {
                        ToolbarNavigationCluster(
                            isHomeActive: activeTab == .springboard,
                            goHome: { activeTab = .springboard }
                        )
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(id: "navigation", placement: .navigation) {
                        ToolbarNavigationCluster(
                            isHomeActive: activeTab == .springboard,
                            goHome: { activeTab = .springboard }
                        )
                    }
                }

                if #available(macOS 26.0, *) {
                    ToolbarItem(id: "tabs", placement: .principal) {
                        WorkspaceTabStrip(
                            tabs: openTabs,
                            activeTab: activeTab,
                            onSelect: { activeTab = $0 },
                            onClose: closeTab
                        )
                        .frame(minWidth: 220, idealWidth: 380, maxWidth: 560)
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(id: "tabs", placement: .principal) {
                        WorkspaceTabStrip(
                            tabs: openTabs,
                            activeTab: activeTab,
                            onSelect: { activeTab = $0 },
                            onClose: closeTab
                        )
                        .frame(minWidth: 220, idealWidth: 380, maxWidth: 560)
                    }
                }

                if #available(macOS 26.0, *) {
                    ToolbarItem(id: "search") {
                        ExpandingSearchField(searchText: $searchText, isExpanded: $isSearchExpanded)
                    }
                    .sharedBackgroundVisibility(.hidden)

                    ToolbarItem(id: "library-actions") {
                        ToolbarActionCluster(
                            openProjectsFolder: store.revealAirstripFolder,
                            importProject: openImportPanelForRunCheck
                        )
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(id: "search") {
                        ExpandingSearchField(searchText: $searchText, isExpanded: $isSearchExpanded)
                    }

                    ToolbarItem(id: "library-actions") {
                        ToolbarActionCluster(
                            openProjectsFolder: store.revealAirstripFolder,
                            importProject: openImportPanelForRunCheck
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch activeTab {
        case .springboard:
            LauncherGrid(
                openProject: openApp,
                openOllama: openOllama,
                searchText: $searchText,
                filter: $libraryFilter
            )
                .background(Color(nsColor: .windowBackgroundColor))

        case .ollama:
            OllamaChatView()

        case .app(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectPage(project: project) {
                    openWeb(id)
                } openAiro: {
                    openOllama()
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

    private func openOllama() {
        if !openTabs.contains(.ollama) {
            openTabs.insert(.ollama, at: 0)
        }
        activeTab = .ollama
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
        case .ollama:
            openTabs.removeAll { $0 == .ollama }
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

    private func runCheckForDroppedItems(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let url = droppedURL(from: item) else { return }
                Task { @MainActor in
                    queueDroppedURLForRunCheck(url)
                }
            }
        }
        return accepted
    }

    private func queueDroppedURLForRunCheck(_ url: URL) {
        if !pendingDropURLs.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
            pendingDropURLs.append(url)
        }

        dropCheckTask?.cancel()
        dropCheckTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                startDropRunCheck()
            }
        }
    }

    private func startDropRunCheck() {
        let urls = pendingDropURLs
        pendingDropURLs = []
        guard !urls.isEmpty else { return }

        isRunningDropCheck = true
        dropCheckResults = []

        let python = dependencyManager.python
        let node = dependencyManager.node
        let ollama = dependencyManager.ollama
        Task {
            var checks: [AirstripRunCheck] = []
            for url in urls {
                let check = await FolderCheck.analyze(url: url, python: python, node: node, ollama: ollama)
                checks.append(check)
            }
            await MainActor.run {
                dropCheckResults = checks
                isRunningDropCheck = false
            }
        }
    }

    private func openImportPanelForRunCheck() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Check"
        panel.message = "Airstrip will check each item before adding it."

        guard panel.runModal() == .OK else { return }
        pendingDropURLs.append(contentsOf: panel.urls)
        startDropRunCheck()
    }

    private func droppedURL(from item: Any?) -> URL? {
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
}

// MARK: - Window chrome

private struct ToolbarNavigationCluster: View {
    let isHomeActive: Bool
    let goHome: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            RuntimeHealthButton()

            Rectangle()
                .fill(.separator.opacity(0.25))
                .frame(width: 1, height: 16)

            NativeToolbarIconButton(
                "Home",
                systemImage: isHomeActive ? "house.fill" : "house",
                isActive: isHomeActive,
                action: goHome
            )
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .airstripGlassCapsule(interactive: false, isToolbarItem: true)
    }
}

private struct NativeToolbarIconButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void
    @State private var isHovering = false

    init(
        _ title: String,
        systemImage: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            if isActive || isHovering {
                Circle()
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.07))
            }
        }
        .noFocusRing()
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
    }
}

private struct ExpandingSearchField: View {
    @Binding var searchText: String
    @Binding var isExpanded: Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                    if !isExpanded {
                        searchText = ""
                        isFocused = false
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .noFocusRing()
            .help(isExpanded ? "Collapse search" : "Search")

            if isExpanded {
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFocused)
                    .frame(width: 120)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        if searchText.isEmpty {
                            isExpanded = false
                            isFocused = false
                        } else {
                            searchText = ""
                        }
                    }
                } label: {
                    Image(systemName: searchText.isEmpty ? "xmark" : "xmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .noFocusRing()
                .help(searchText.isEmpty ? "Collapse search" : "Clear search")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, isExpanded ? 6 : 3)
        .frame(height: 34)
        .airstripGlassCapsule(interactive: true, isToolbarItem: true)
        .onChange(of: isExpanded) { expanded in
            if expanded {
                isFocused = true
            }
        }
    }
}

private struct ToolbarActionCluster: View {
    let openProjectsFolder: () -> Void
    let importProject: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            clusterButton("Open Projects Folder", systemImage: "folder", action: openProjectsFolder)

            Rectangle()
                .fill(.separator.opacity(0.25))
                .frame(width: 1, height: 16)

            clusterButton("Import Project", systemImage: "plus", action: importProject)
        }
        .padding(.horizontal, 4)
        .frame(height: 34)
        .airstripGlassCapsule(interactive: false, isToolbarItem: true)
    }

    private func clusterButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        ToolbarCircleIconButton(title: title, systemImage: systemImage, action: action)
    }
}

private struct ToolbarCircleIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            if isHovering {
                Circle()
                    .fill(Color.primary.opacity(0.07))
            }
        }
        .noFocusRing()
        .help(title)
        .accessibilityLabel(title)
        .onHover { isHovering = $0 }
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

    private let defaultTabWidth: CGFloat = 120
    private let minTabWidth: CGFloat = 50
    private let maxAreaWidth: CGFloat = 480
    private let paddingHorizontal: CGFloat = 6
    private let paddingVertical: CGFloat = 5
    private let spacing: CGFloat = 6

    private var computedTabWidth: CGFloat {
        guard !tabs.isEmpty else { return defaultTabWidth }
        
        var extraWidth = 2 * paddingHorizontal + CGFloat(groups.count - 1) * spacing
        for group in groups {
            if group.tabs.count > 1 {
                extraWidth += 4 + CGFloat(group.tabs.count - 1) * 2
            }
        }
        
        let availableForChips = maxAreaWidth - extraWidth
        let sharedWidth = availableForChips / CGFloat(tabs.count)
        return min(defaultTabWidth, max(minTabWidth, sharedWidth))
    }

    private var containerWidth: CGFloat {
        guard !tabs.isEmpty else { return defaultTabWidth + 2 * paddingHorizontal }
        
        var width = 2 * paddingHorizontal + CGFloat(groups.count - 1) * spacing
        let tabW = computedTabWidth
        for group in groups {
            let chipsWidth = CGFloat(group.tabs.count) * tabW
            if group.tabs.count > 1 {
                width += chipsWidth + 4 + CGFloat(group.tabs.count - 1) * 2
            } else {
                width += chipsWidth
            }
        }
        return width
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                if groups.isEmpty {
                    Text("No Open Windows")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: defaultTabWidth, height: 28, alignment: .center)
                } else {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
            }
            .padding(.horizontal, paddingHorizontal)
            .padding(.vertical, paddingVertical)
        }
        .frame(width: containerWidth)
        .background(tabWellBackground)
    }

    private var tabWellBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func groupView(_ group: TabGroup) -> some View {
        let tabW = computedTabWidth
        if group.tabs.count > 1, let projectID = group.projectID {
            let tint = store.projects.first(where: { $0.id == projectID })
                .map { ProjectTint.color(for: $0.name) } ?? .accentColor

            HStack(spacing: 2) {
                ForEach(group.tabs) { tab in
                    tabChip(tab, width: tabW)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
            )
        } else if let tab = group.tabs.first {
            tabChip(tab, width: tabW)
        }
    }

    @ViewBuilder
    private func tabChip(_ tab: WorkspaceTab, width: CGFloat) -> some View {
        switch tab {
        case .springboard:
            SpringboardTabChip(isActive: activeTab == tab, width: width) {
                onSelect(tab)
            }
        case .ollama:
            OllamaTabChip(
                isActive: activeTab == tab,
                select: { onSelect(tab) },
                close: { onClose(tab) },
                width: width
            )
        case .app(let id), .web(let id):
            if let project = store.projects.first(where: { $0.id == id }) {
                ProjectTabChip(
                    project: project,
                    tab: tab,
                    isActive: activeTab == tab,
                    isRunning: store.runtimeStates[id]?.isRunning == true,
                    select: { onSelect(tab) },
                    close: { onClose(tab) },
                    width: width
                )
            }
        }
    }
}

private struct SpringboardTabChip: View {
    let isActive: Bool
    let width: CGFloat
    let select: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)

                Text("Springboard")
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: width, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .background(chipBackground(isActive: isActive, isHovering: isHovering))
        .accessibilityLabel("Springboard")
        .onHover { isHovering = $0 }
    }
}

private struct OllamaTabChip: View {
    let isActive: Bool
    let select: () -> Void
    let close: () -> Void
    let width: CGFloat

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: select) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .teal], startPoint: .top, endPoint: .bottom)
                        )

                    Text("Airo")
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
                .padding(.trailing, 28)
                .padding(.vertical, 5)
                .frame(width: width, height: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noFocusRing()
            .accessibilityLabel("Airo")

            closeButton
                .opacity(isHovering || isActive ? 1 : 0.45)
                .padding(.trailing, 6)
        }
        .frame(width: width, height: 28)
        .background(chipBackground(isActive: isActive, isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Circle())
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .accessibilityLabel("Close Airo tab")
        .help("Close tab")
    }
}

private struct ProjectTabChip: View {
    let project: AirstripProject
    let tab: WorkspaceTab
    let isActive: Bool
    let isRunning: Bool
    let select: () -> Void
    let close: () -> Void
    let width: CGFloat

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: select) {
                HStack(spacing: 4) {
                    if tab.isWeb {
                        Image(systemName: "globe")
                            .font(.system(size: 10.5))
                            .foregroundStyle(isActive ? ProjectTint.color(for: project.name) : .secondary)
                    } else {
                        ProjectIconBadge(project: project, size: 13)
                    }

                    Text(tab.isWeb ? "Web UI" : project.name)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)

                    if isRunning, !tab.isWeb {
                        Circle()
                            .fill(.green)
                            .frame(width: 5, height: 5)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 28)
                .padding(.vertical, 5)
                .frame(width: width, height: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .noFocusRing()
            .accessibilityLabel(tab.isWeb ? "\(project.name) web UI" : project.name)

            closeButton
                .opacity(isHovering || isActive ? 1 : 0.45)
                .padding(.trailing, 6)
        }
        .frame(width: width, height: 28)
        .background(chipBackground(isActive: isActive, isHovering: isHovering))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
                .background(isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Circle())
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .accessibilityLabel("Close \(tab.isWeb ? "web UI" : project.name) tab")
        .help("Close tab")
    }
}

private func chipBackground(isActive: Bool, isHovering: Bool) -> some View {
    Group {
        if isActive {
            Color.clear
                .airstripGlassPanel(cornerRadius: 8, interactive: true)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.05) : Color.clear)
        }
    }
}

// MARK: - Running strip

/// Always-visible bar listing everything that is currently running, with
/// ports, elapsed time, and stop buttons.
private struct RunningStrip: View {
    @Environment(\.airstripVisualStyle) private var visualStyle
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
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator.opacity(visualStyle.separatorOpacity))
                .frame(height: 1)
        }
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
                .noFocusRing()
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
            .noFocusRing()
            .help("Stop \(project.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .airstripGlassPanel(cornerRadius: 8, tint: state.isPreparing ? .yellow : .green, interactive: true, fallbackOpacity: 0.45)
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

/// Kills the macOS focus ring that otherwise lingers on toolbar buttons
/// after their popover closes.
extension View {
    @ViewBuilder
    func noFocusRing() -> some View {
        if #available(macOS 14.0, *) {
            self.focusable(false)
                .focusEffectDisabled()
        } else {
            self.focusable(false)
        }
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .noFocusRing()
        .accessibilityLabel(title)
    }
}

private struct RuntimeHealthButton: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @State private var isHovering = false

    private var anyMissing: Bool {
        [dependencyManager.python, dependencyManager.node, dependencyManager.homebrew, dependencyManager.ollama]
            .contains(.missing)
    }

    private var anyChecking: Bool {
        [dependencyManager.python, dependencyManager.node, dependencyManager.homebrew, dependencyManager.ollama]
            .contains(.unknown)
    }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                store.isSidebarOpen.toggle()
            }
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(symbolColor)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .help("Python, Node/npm, Homebrew, and Ollama status")
        .buttonStyle(.plain)
        .background {
            if isHovering || store.isSidebarOpen {
                Circle()
                    .fill(Color.primary.opacity(0.07))
            }
        }
        .noFocusRing()
        .accessibilityLabel("Runtime status")
        .onHover { isHovering = $0 }
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

/// Compact status panel: the three runtime dependencies plus a switch for
/// the local Ollama server. Capability details live on the dashboard.
private struct RuntimeHealthPopover: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @EnvironmentObject private var ollama: OllamaManager

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Runtime")
                    .font(.headline)

                Spacer()

                Button {
                    dependencyManager.refresh()
                    ollama.refreshServerStatus()
                    store.refreshProjectsFromDisk()
                } label: {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .noFocusRing()
                .help("Check dependencies, the Ollama server, and project folders again")
            }

            RuntimeRow(
                name: "Python",
                detail: "Runs automation scripts",
                status: dependencyManager.python,
                install: dependencyManager.installPython
            )

            RuntimeRow(
                name: "Node/npm",
                detail: "Runs web app projects",
                status: dependencyManager.node,
                install: dependencyManager.installNode
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

            Divider()

            OllamaServerSwitch()
        }
        .padding(16)
        .frame(width: 340)
        .noFocusRing()
    }
}

/// On/off switch for the local Ollama server, shared by the health popover
/// and the dashboard.
struct OllamaServerSwitch: View {
    @EnvironmentObject private var ollama: OllamaManager

    private var isOn: Binding<Bool> {
        Binding(
            get: {
                ollama.serverStatus.isRunning || ollama.serverStatus == .starting
            },
            set: { on in
                if on {
                    ollama.startServe()
                } else {
                    ollama.stopServer()
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text("Ollama Server")
                    .font(.system(size: 12, weight: .medium))

                Text(ollama.serverStatus.label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if ollama.serverStatus == .notInstalled {
                Text("Not installed")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .disabled(ollama.serverStatus == .unknown || ollama.serverStatus == .starting)
                    .help(ollama.serverStatus.isRunning ? "Stop the Ollama server" : "Start the Ollama server")
            }
        }
    }

    private var color: Color {
        switch ollama.serverStatus {
        case .running: return .green
        case .starting, .unknown: return .yellow
        case .stopped, .notInstalled: return .orange
        }
    }
}

struct RuntimeRow: View {
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
                    .airstripGlassButton()
                    .controlSize(.small)
                    .noFocusRing()
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

// MARK: - Drop state

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
