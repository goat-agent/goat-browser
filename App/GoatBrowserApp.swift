import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppDatabase.shared
        if !GoatCEF.initializeCEF() {
            NSLog("[GoatBrowser] CEF initialization failed.")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        GoatCEF.shutdown()
    }
}

struct BrowserModelKey: FocusedValueKey {
    typealias Value = BrowserViewModel
}

extension FocusedValues {
    var browserModel: BrowserViewModel? {
        get { self[BrowserModelKey.self] }
        set { self[BrowserModelKey.self] = newValue }
    }
}

@main
struct GoatBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.titleBar)
        .commands { BrowserCommands() }

        Settings {
            SettingsView()
        }
    }
}

struct RootView: View {
    @State private var model = BrowserViewModel()
    @State private var settings = AppSettings.shared

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 900, minHeight: 600)
            .focusedSceneValue(\.browserModel, model)
            .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch settings.theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct BrowserCommands: Commands {
    @FocusedValue(\.browserModel) private var model

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") { model?.openCommandBarForNewTab() }
                .keyboardShortcut("t")
            Button("Reopen Closed Tab") { model?.reopenLastClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Close Tab") { model?.closeActiveTab() }
                .keyboardShortcut("w")
        }

        CommandMenu("Navigate") {
            Button("Open Location…") { model?.openCommandBarForActiveTab() }
                .keyboardShortcut("l")
            Button("Find…") { model?.openFind() }
                .keyboardShortcut("f")
            Divider()
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[")
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]")
            Button("Reload") { model?.reload() }
                .keyboardShortcut("r")
            Divider()
            Button("Next Tab") { model?.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { model?.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            Button("Zoom In") { model?.zoomIn() }
                .keyboardShortcut("=")
            Button("Zoom Out") { model?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { model?.zoomReset() }
                .keyboardShortcut("0")
            Divider()
            Button("Toggle Sidebar") { model?.toggleSidebar() }
                .keyboardShortcut("\\")
            Button("Developer Tools") { model?.showDevTools() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Bookmarks") {
            Button("Bookmark This Tab") { model?.bookmarkCurrentTab() }
                .keyboardShortcut("d")
        }
    }
}
