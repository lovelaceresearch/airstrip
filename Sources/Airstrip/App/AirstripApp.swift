import AppKit
import SwiftUI

@main
struct AirstripApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore()
    @StateObject private var dependencyManager = DependencyManager()
    @StateObject private var ollamaManager = OllamaManager()
    @StateObject private var visualSettings = VisualSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(dependencyManager)
                .environmentObject(ollamaManager)
                .environmentObject(visualSettings)
                .environment(\.airstripVisualStyle, visualSettings.style)
                .softenedByVisualSettings()
                .frame(minWidth: 780, minHeight: 560)
                .task {
                    store.load()
                    dependencyManager.refresh()
                    ollamaManager.refreshServerStatus()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Project...") {
                    store.importWithPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
