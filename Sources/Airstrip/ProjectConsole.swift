import SwiftUI

struct ProjectConsole: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    let project: AirstripProject

    private var state: ProjectRuntimeState {
        store.runtimeStates[project.id] ?? ProjectRuntimeState()
    }

    private var actions: [ProjectAction] {
        store.actions(for: project)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)

                    Text(project.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let lastExitCode = state.lastExitCode, !state.isRunning {
                    Text("Exited \(lastExitCode)")
                        .font(.caption)
                        .foregroundStyle(lastExitCode == 0 ? Color.secondary : Color.red)
                }

                if state.activeWebURL != nil, state.isRunning {
                    Button {
                        store.openWebUI(for: project)
                    } label: {
                        Label("Open Web UI", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    store.toggle(project)
                } label: {
                    if state.isPreparing {
                        Label("Checking...", systemImage: "hourglass")
                    } else {
                        Label(state.isRunning ? "Stop" : "Run", systemImage: state.isRunning ? "stop.fill" : "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isPreparing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if !state.missingTools.isEmpty {
                MissingToolsBanner(project: project, tools: state.missingTools)
                Divider()
            }

            if !actions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(actions) { action in
                            Button {
                                store.run(project, action: action)
                            } label: {
                                Label(action.name, systemImage: action.isDefault ? "play.fill" : "terminal")
                            }
                            .buttonStyle(.bordered)
                            .disabled(state.isRunning)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                Divider()
            }

            ScrollView {
                Text(state.log.isEmpty ? "No logs yet." : state.log)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(state.log.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .frame(height: 190)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(.regularMaterial)
    }
}

private struct MissingToolsBanner: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var dependencyManager: DependencyManager
    let project: AirstripProject
    let tools: [ProjectTool]

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("This project needs tools that are not installed yet.")
                    .font(.caption.weight(.semibold))

                Text(tools.map(\.command).joined(separator: ", "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ForEach(tools) { tool in
                if let package = tool.brew {
                    Button("Install \(tool.command)") {
                        dependencyManager.installBrewPackage(package)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Button("Dismiss") {
                store.dismissMissingTools(for: project)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }
}
