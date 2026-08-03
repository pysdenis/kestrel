import SwiftUI

/// Kestrel's UI target. Two scenes over one shared model:
///   • a menu-bar popover (always available, LSUIElement accessory), and
///   • a full window ("Open Kestrel") with the complete feature set.
/// All data and actions come from KestrelCore — this target only renders and wires.
///
/// Packaging into a runnable Kestrel.app (LSUIElement bundle, signing, notarization) is
/// handled by scripts/build-app.sh and docs/RELEASE.md.
@main
struct KestrelApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Kestrel", systemImage: "bird.fill") {
            MenuBarView().environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Kestrel", id: "main") {
            MainWindow().environmentObject(model)
        }
        .defaultSize(width: 900, height: 640)
    }
}
