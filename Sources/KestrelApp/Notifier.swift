import Foundation
import UserNotifications

/// Local-only notifications (invariant #7: nothing leaves the device). Used for honest,
/// actionable alerts — low disk space, a real security finding. Guarded so it never
/// crashes when the binary runs without an app bundle (e.g. `swift run`), since
/// `UNUserNotificationCenter.current()` requires a bundle identifier.
@MainActor final class Notifier {
    static let shared = Notifier()

    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorization() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Post a notification, checking the live authorization status first — so a notify
    /// that races ahead of the async authorization callback isn't silently dropped.
    func notify(title: String, body: String, id: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
