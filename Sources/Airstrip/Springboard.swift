import AppKit
import SwiftUI

struct Springboard: View {
    @EnvironmentObject private var store: ProjectStore
    @Binding var selection: AirstripProject.ID?

    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 156), spacing: 18)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(store.projects) { project in
                    ProjectIcon(project: project, isSelected: selection == project.id)
                        .onTapGesture {
                            selection = project.id
                        }
                        .onTapGesture(count: 2) {
                            selection = project.id
                            store.toggle(project)
                        }
                        .contextMenu {
                            Button(projectState(project).isRunning ? "Stop" : "Run") {
                                selection = project.id
                                store.toggle(project)
                            }

                            if !projectState(project).isRunning {
                                ForEach(store.actions(for: project)) { action in
                                    Button(action.name) {
                                        selection = project.id
                                        store.run(project, action: action)
                                    }
                                }
                            }

                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([project.path])
                            }

                            Button("Open Logs") {
                                selection = project.id
                            }

                            Divider()

                            Button("Remove from Airstrip", role: .destructive) {
                                store.remove(project)
                            }
                        }
                }
            }
            .padding(28)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func projectState(_ project: AirstripProject) -> ProjectRuntimeState {
        store.runtimeStates[project.id] ?? ProjectRuntimeState()
    }
}

private struct ProjectIcon: View {
    @EnvironmentObject private var store: ProjectStore
    let project: AirstripProject
    let isSelected: Bool

    private var state: ProjectRuntimeState {
        store.runtimeStates[project.id] ?? ProjectRuntimeState()
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconFill)
                    .overlay {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 5)

                if state.isRunning {
                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }
            }

            Text(project.name)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 38, alignment: .top)
        }
        .frame(width: 132, height: 136)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
    }

    private var iconFill: LinearGradient {
        LinearGradient(
            colors: [.teal, .indigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
