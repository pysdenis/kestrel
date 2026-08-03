import SwiftUI
import AppKit

/// App lifecycle: make sure the main window is actually visible on launch and reopens
/// when the app is re-activated (Dock click / `open`), so the UI is never stranded
/// behind a hidden menu-bar icon.
final class KestrelAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // stay alive in the menu bar after the window is closed
    }
}

/// Kestrel's UI target: a full window plus a menu-bar popover, over one shared model.
/// The Window scene is listed first so it opens at launch. All data and actions come
/// from KestrelCore — this target only renders and wires.
@main
struct KestrelApp: App {
    @NSApplicationDelegateAdaptor(KestrelAppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Kestrel", id: "main") {
            MainWindow().environmentObject(model)
        }
        .defaultSize(width: 980, height: 700)

        MenuBarExtra("Kestrel", systemImage: "bird.fill") {
            MenuBarView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}
