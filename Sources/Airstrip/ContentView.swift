import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @State private var selection: AirstripProject.ID?
    @State private var isDropTargeted = false

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 320)
        } content: {
            ZStack {
                Springboard(selection: $selection)
                if store.projects.isEmpty {
                    EmptyImportView()
                }
            }
            .navigationSplitViewColumnWidth(min: 360, ideal: 560)
        } detail: {
            ProjectWorkspace(selection: $selection)
                .navigationSplitViewColumnWidth(min: 360, ideal: 500, max: 720)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.importWithPanel()
                } label: {
                    Label("Import Project", systemImage: "plus")
                }

                Button {
                    store.revealAirstripFolder()
                } label: {
                    Label("Open Projects Folder", systemImage: "folder")
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
                    .padding(18)
                    .allowsHitTesting(false)
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
}

private struct ProjectWorkspace: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var selection: AirstripProject.ID?

    private var visibleProjects: [AirstripProject] {
        var result: [AirstripProject] = []

        if let selection,
           let selectedProject = store.projects.first(where: { $0.id == selection }) {
            result.append(selectedProject)
        }

        for project in store.projects {
            let state = store.runtimeStates[project.id]
            let shouldShow = state?.isRunning == true || state?.isPreparing == true
            if shouldShow, !result.contains(where: { $0.id == project.id }) {
                result.append(project)
            }
        }

        return result
    }

    private var tabSelection: Binding<AirstripProject.ID?> {
        Binding(
            get: {
                if let selection,
                   visibleProjects.contains(where: { $0.id == selection }) {
                    return selection
                }
                return visibleProjects.first?.id
            },
            set: { newValue in
                selection = newValue
            }
        )
    }

    var body: some View {
        if visibleProjects.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)

                Text("Select an app")
                    .font(.title3.weight(.semibold))

                Text("Controls, actions, logs, and running app tabs appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        } else {
            TabView(selection: tabSelection) {
                ForEach(visibleProjects) { project in
                    ProjectConsole(project: project)
                        .tabItem {
                            Label(
                                project.name,
                                systemImage: store.runtimeStates[project.id]?.isRunning == true ? "play.circle.fill" : "app"
                            )
                        }
                        .tag(Optional(project.id))
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    @Binding var selection: AirstripProject.ID?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Airstrip")
                    .font(.system(size: 28, weight: .bold))

                Text("Local automations, one click away.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            DependencyPanel()
                .padding(.horizontal, 14)

            WebServerPanel()
                .padding(.horizontal, 14)
                .padding(.top, 12)

            Button {
                store.revealAirstripFolder()
            } label: {
                Label("Open Projects Folder", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 14)
            .padding(.top, 12)

            Button {
                store.refreshProjectsFromDisk()
            } label: {
                Label("Sync Projects", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct WebServerPanel: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Web Servers")
                    .font(.headline)

                Spacer()

                Text("\(store.runningWebServers.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if store.runningWebServers.isEmpty {
                Text("No local web apps running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.runningWebServers) { server in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(.green)
                                .frame(width: 8, height: 8)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.project.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)

                                Text(server.actionName ?? "Web action")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(":\(server.port)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                store.openWebUI(server)
                            } label: {
                                Label("Open", systemImage: "safari")
                            }

                            Button(role: .destructive) {
                                store.stopWebServer(server)
                            } label: {
                                Label("Stop", systemImage: "stop.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if server.id != store.runningWebServers.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DependencyPanel: View {
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
                .help("Refresh runtime status")
            }

            DependencyRow(name: "Python", status: dependencyManager.python)
            DependencyRow(name: "Homebrew", status: dependencyManager.homebrew)
            DependencyRow(name: "Ollama", status: dependencyManager.ollama)

            Divider()

            Button {
                dependencyManager.installPython()
            } label: {
                Label("Install Python", systemImage: "arrow.down.circle")
            }
            .disabled(dependencyManager.python != .missing)

            Button {
                dependencyManager.installHomebrew()
            } label: {
                Label("Install Homebrew", systemImage: "terminal")
            }
            .disabled(dependencyManager.homebrew != .missing)

            Button {
                dependencyManager.installOllama()
            } label: {
                Label("Install Ollama", systemImage: "arrow.down.circle")
            }
            .disabled(dependencyManager.ollama != .missing)
        }
        .buttonStyle(.bordered)
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DependencyRow: View {
    let name: String
    let status: DependencyStatus

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(name)
            Spacer()
            Text(status.label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.caption)
    }

    private var color: Color {
        switch status {
        case .unknown:
            return .yellow
        case .available:
            return .green
        case .missing:
            return .red
        }
    }
}

private struct EmptyImportView: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Drop an automation folder here")
                .font(.title2.weight(.semibold))

            Text("Airstrip copies it into its workspace and turns it into a launchable icon.")
                .foregroundStyle(.secondary)

            Button {
                store.importWithPanel()
            } label: {
                Label("Import Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .multilineTextAlignment(.center)
        .padding(40)
    }
}
