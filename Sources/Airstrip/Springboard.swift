import AppKit
import SwiftUI

// MARK: - Launcher grid

struct LauncherGrid: View {
    @EnvironmentObject private var store: ProjectStore
    let openProject: (AirstripProject.ID) -> Void
    let openOllama: () -> Void

    // Fixed column width and leading alignment: adaptive width ranges and
    // centered layout both make tiles slide around while the window resizes.
    // Left-anchored fixed columns only reflow at clean breakpoints, like
    // Finder's icon view.
    private let columns = [
        GridItem(.adaptive(minimum: 132, maximum: 132), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DashboardHeader()

                Text("Apps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    OllamaTile(open: openOllama)

                    ForEach(store.projects) { project in
                        ProjectTile(project: project) {
                            openProject(project.id)
                        }
                        .onTapGesture(count: 2) {
                            openProject(project.id)
                            store.toggle(project)
                        }
                        .onTapGesture {
                            openProject(project.id)
                        }
                        .contextMenu {
                            tileMenu(for: project)
                        }
                    }
                }

                if store.projects.isEmpty {
                    ImportHintCard()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func tileMenu(for project: AirstripProject) -> some View {
        let state = store.runtimeStates[project.id] ?? ProjectRuntimeState()

        Button(state.isRunning ? "Stop" : "Run") {
            openProject(project.id)
            store.toggle(project)
        }

        if state.isRunning, state.activeWebURL != nil {
            Button("Open in Browser") {
                store.openWebUI(for: project)
            }
        }

        if !state.isRunning {
            let actions = store.actions(for: project)
            if actions.count > 1 {
                Menu("Run Action") {
                    ForEach(actions) { action in
                        Button(action.name) {
                            openProject(project.id)
                            store.run(project, action: action)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Show Details") {
            openProject(project.id)
        }

        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([project.path])
        }

        Divider()

        Button("Remove from Airstrip", role: .destructive) {
            store.remove(project)
        }
    }
}

// MARK: - Import hint

/// Shown under the grid when no automations are imported yet; the dashboard
/// stays visible above it.
private struct ImportHintCard: View {
    @EnvironmentObject private var store: ProjectStore

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(.quaternary)
                    .frame(width: 58, height: 58)

                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Drop an automation folder anywhere in this window")
                    .font(.system(size: 13, weight: .semibold))

                Text("It becomes an app icon you can run with one click.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.importWithPanel()
            } label: {
                Label("Choose Folder...", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

// MARK: - AI Studio tile

/// Built-in AI app: rendered like any other tile but opens the integrated
/// AI Studio tab instead of running a project.
private struct OllamaTile: View {
    @EnvironmentObject private var ollama: OllamaManager
    let open: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 86 * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 86 * 0.225, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .frame(width: 86, height: 86)
                    .shadow(color: .black.opacity(isHovering ? 0.22 : 0.12), radius: isHovering ? 13 : 9, y: 5)
                    .scaleEffect(isHovering ? 1.04 : 1)

                if ollama.serverStatus.isRunning {
                    PulsingDot(color: .green)
                        .offset(x: 36, y: 36)
                }
            }
            .frame(width: 92, height: 92)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)

            VStack(spacing: 3) {
                Text("AI Studio")
                    .font(.system(size: 13, weight: .medium))

                Text(captionText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(ollama.serverStatus.isRunning ? .green : .secondary)
                    .lineLimit(1)
            }
            .frame(height: 46, alignment: .top)
        }
        .frame(width: 124)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovering ? Color.primary.opacity(0.045) : Color.clear)
        )
        .onHover { isHovering = $0 }
        .onTapGesture(perform: open)
    }

    private var captionText: String {
        switch ollama.serverStatus {
        case .running:
            return "Running"
        case .unknown:
            return "Local + API models"
        default:
            return ollama.serverStatus.label
        }
    }
}

// MARK: - Tile

private struct ProjectTile: View {
    @EnvironmentObject private var store: ProjectStore
    let project: AirstripProject
    let onActivate: () -> Void

    @State private var isHovering = false

    private var state: ProjectRuntimeState {
        store.runtimeStates[project.id] ?? ProjectRuntimeState()
    }

    private var status: ProjectDisplayStatus {
        ProjectDisplayStatus(state)
    }

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                ProjectIconBadge(project: project, size: 86)
                    .shadow(color: .black.opacity(isHovering ? 0.22 : 0.12), radius: isHovering ? 13 : 9, y: 5)
                    .scaleEffect(isHovering ? 1.04 : 1)

                if isHovering {
                    RunStopOverlay(isRunning: state.isRunning, isPreparing: state.isPreparing) {
                        onActivate()
                        store.toggle(project)
                    }
                }

                statusBadge
                    .offset(x: 36, y: 36)
            }
            .frame(width: 92, height: 92)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)

            VStack(spacing: 3) {
                Text(project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                if needsAcknowledgment {
                    // Clicking the badge marks it as checked without opening
                    // the app; the run history stays in the app tab.
                    Button {
                        store.acknowledge(project.id)
                    } label: {
                        captionLabel
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(statusCaptionColor.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Mark as checked")
                } else {
                    captionLabel
                }
            }
            .frame(height: 46, alignment: .top)
        }
        .frame(width: 124)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isHovering ? Color.primary.opacity(0.045) : Color.clear)
        )
        .onHover { isHovering = $0 }
    }

    // Only live activity sits on the icon itself; results moved to the
    // caption under the name.
    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .running:
            PulsingDot(color: .green)
        case .preparing:
            PulsingDot(color: .yellow)
        case .needsAttention, .finished, .idle:
            EmptyView()
        }
    }

    private var needsAcknowledgment: Bool {
        switch status {
        case .finished, .needsAttention:
            return !state.acknowledged
        default:
            return false
        }
    }

    private var captionLabel: some View {
        HStack(spacing: 3) {
            if let icon = statusCaptionIcon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }

            Text(statusCaption)
                .font(.system(size: 10.5))
                .lineLimit(1)
        }
        .foregroundStyle(statusCaptionColor)
    }

    private var statusCaption: String {
        switch status {
        case .idle:
            return " "
        case .preparing:
            return "Checking..."
        case .running:
            if let port = state.activeWebPort {
                return "Running · :\(port)"
            }
            return state.activeActionName.map { "Running · \($0)" } ?? "Running"
        case .finished:
            return "Completed"
        case .needsAttention:
            return "Needs attention"
        }
    }

    private var statusCaptionIcon: String? {
        switch status {
        case .finished:
            return state.acknowledged ? "checkmark.circle" : "checkmark.circle.fill"
        case .needsAttention:
            return state.acknowledged ? "checkmark.circle" : "exclamationmark.circle.fill"
        default:
            return nil
        }
    }

    private var statusCaptionColor: Color {
        // Acknowledged results fade to gray; unseen ones keep their color.
        switch status {
        case .running:
            return .green
        case .finished:
            return state.acknowledged ? .secondary : .green
        case .needsAttention:
            return state.acknowledged ? .secondary : .orange
        default:
            return .secondary
        }
    }
}

private struct RunStopOverlay: View {
    let isRunning: Bool
    let isPreparing: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.45))
                    .background(.ultraThinMaterial, in: Circle())

                Image(systemName: isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .disabled(isPreparing)
        .help(isRunning ? "Stop" : "Run")
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            .background(
                Circle()
                    .fill(color.opacity(0.4))
                    .scaleEffect(pulsing ? 2.0 : 1.0)
                    .opacity(pulsing ? 0 : 0.8)
                    .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulsing)
            )
            .onAppear { pulsing = true }
    }
}

// MARK: - Icon

/// Project identity icon: the manifest's icon image when it exists, otherwise
/// a deterministic gradient derived from the project name with its initials.
struct ProjectIconBadge: View {
    let project: AirstripProject
    let size: CGFloat

    var body: some View {
        Group {
            if let image = customIcon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .fill(gradient)
                    .overlay {
                        Text(initials)
                            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.35), .white.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
    }

    private var customIcon: NSImage? {
        guard let iconName = project.manifest.icon, !iconName.isEmpty else { return nil }
        let url = project.path.appendingPathComponent(iconName)
        let key = url.path as NSString
        if let cached = Self.iconCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        Self.iconCache.setObject(image, forKey: key)
        return image
    }

    private static let iconCache = NSCache<NSString, NSImage>()

    private var initials: String {
        let words = project.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty {
            return "?"
        }
        return letters.map(String.init).joined().uppercased()
    }

    private var gradient: LinearGradient {
        ProjectTint.gradient(for: project.name)
    }
}

/// Stable per-project colors shared by tiles, tab groups, and headers.
enum ProjectTint {
    private static let palette: [(Color, Color)] = [
        (.blue, .indigo),
        (.teal, .blue),
        (.indigo, .purple),
        (.orange, .pink),
        (.green, .teal),
        (.pink, .purple),
        (.cyan, .blue),
        (.purple, .blue)
    ]

    static func colors(for name: String) -> (Color, Color) {
        // hashValue is randomly seeded per launch; use a stable digest so a
        // project keeps the same color across launches.
        let digest = name.unicodeScalars.reduce(into: UInt64(5381)) { result, scalar in
            result = result &* 33 &+ UInt64(scalar.value)
        }
        return palette[Int(digest % UInt64(palette.count))]
    }

    static func color(for name: String) -> Color {
        colors(for: name).0
    }

    static func gradient(for name: String) -> LinearGradient {
        let pair = colors(for: name)
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
