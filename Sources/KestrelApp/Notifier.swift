import Foundation
import UserNotifications

/// Local-only notifications (invariant #7: nothing leaves the device). Used for honest,
/// actionable alerts — low disk space, a real security finding. Guarded so it never
/// crashes when the binary runs without an app bundle (e.g. `swift run`), since
/// `UNUserNotificationCenter.current()` requires a bundle identifier.
@MainActor final class Notifier {
    static let shared = Notifier()
    private var authorized = false

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func notify(title: String, body: String, id: String) {
        guard available, authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
