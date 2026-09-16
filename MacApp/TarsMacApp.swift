import SwiftUI

@main
struct TarsMacApp: App {
    @StateObject private var model = AppModel.shared
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    init() {
        // Without a menu bar item the only way back in is reopening the app, which must show the window.
        if !UserDefaults.standard.bool(forKey: "showMenuBarItem") && UserDefaults.standard.object(forKey: "showMenuBarItem") != nil {
            UserDefaults.standard.set(false, forKey: "hideWindowAtStartup")
        }
    }

    var body: some Scene {
        Window("Tars", id: "settings") {
            SettingsView().environmentObject(model).onAppear { model.start() }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "hideWindowAtStartup") ? .suppressed : .presented)
        .restorationBehavior(.disabled)

        // Guarded binding: MenuBarExtra re-writes isInserted on every update; an unconditional
        // @Published set would publish → re-render → set … and pin the main thread.
        MenuBarExtra("Tars", systemImage: menuIcon, isInserted: Binding(
            get: { model.showMenuBarItem },
            set: { if $0 != model.showMenuBarItem { model.showMenuBarItem = $0 } })) {
            MenuContent().environmentObject(model).onAppear { model.start() }
        }
    }

    private var menuIcon: String {
        switch model.state {
        case "working": return "eyes"
        case "approval": return "exclamationmark.circle.fill"
        case "completed": return "checkmark.circle"
        default: return "eyes.inverse"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the server here: with the window suppressed and the menu closed, no view ever appears.
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { NSApp.activate(); NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("\(model.state.capitalized) · \(model.sourceAvailable ? "agent connected" : "no agent events")")
        if let detail = model.detail { Text(detail).lineLimit(1) }
        Divider()
        Text(model.developmentMode ? "Development mode · no pairing" : "Pairing code: \(model.pairingCode)")
        Button("Settings…") { openWindow(id: "settings"); NSApp.activate() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Tars") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
