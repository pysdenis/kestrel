import SwiftUI

/// Menu-bar entry point. Lives in the status bar; clicking the icon opens the SwiftUI
/// dashboard in a popover-style window. All data comes from `KestrelCore` — this target
/// only renders it (see docs/ARCHITECTURE.md, "zlaté pravidlo").
///
/// Note: to run as a proper accessory app this target still needs bundling and an
/// `LSUIElement` Info.plist (Phase 7). It compiles today so the UI can be developed
/// against the live Core.
@main
struct KestrelApp: App {
    var body: some Scene {
        MenuBarExtra("Kestrel", systemImage: "bird.fill") {
            DashboardView()
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}
