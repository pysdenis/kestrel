import Foundation

/// Detects whether the app has been granted Full Disk Access. Several honest features —
/// emptying the Trash, scanning `~/Library/Mail`, reading some caches — depend on it, and
/// without it macOS silently returns "Operation not permitted" or an empty listing, which
/// makes those features look broken. We probe a folder that always exists and is always
/// gated behind Full Disk Access (`~/.Trash`): if we can list it, access is granted.
public enum FullDiskAccess {
    public static func isGranted(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let probe = home.appendingPathComponent(".Trash")
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: probe.path)
            return true
        } catch {
            return false
        }
    }

    /// The macOS Settings deep-link to the Full Disk Access list.
    public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
}
