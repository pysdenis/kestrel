import Foundation
import SQLite3

/// One privacy grant: which app (client) may use which protected resource (service),
/// and whether it is currently allowed. Read straight from the user's TCC database —
/// Kestrel reports the real state, never guesses.
public struct TCCPermission: Sendable, Equatable {
    public let service: String     // raw TCC service, e.g. "kTCCServiceCamera"
    public let client: String      // bundle id or path
    public let allowed: Bool

    public init(service: String, client: String, allowed: Bool) {
        self.service = service
        self.client = client
        self.allowed = allowed
    }
}

/// Reads the user's TCC (Transparency, Consent & Control) database read-only, so the app
/// can show which apps have Camera / Microphone / Full Disk Access / etc. Requires Full
/// Disk Access to open the database; without it the read simply returns nothing (honest —
/// no fabricated permissions). System-wide grants under `/Library` need root and are out
/// of scope; this covers per-user grants, which is what most people care about.
public struct TCCReader {
    private let dbPath: String

    public init(dbPath: String = (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")) {
        self.dbPath = dbPath
    }

    public func permissions() -> [TCCPermission] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        // Modern schema uses `auth_value` (0 denied, 2 allowed, 3 limited); older macOS
        // used a boolean `allowed`. Try the modern query first, fall back to the old one.
        if let rows = query(db, "SELECT service, client, auth_value FROM access", authValued: true) { return rows }
        if let rows = query(db, "SELECT service, client, allowed FROM access", authValued: false) { return rows }
        return []
    }

    private func query(_ db: OpaquePointer?, _ sql: String, authValued: Bool) -> [TCCPermission]? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        var out: [TCCPermission] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let s = sqlite3_column_text(stmt, 0), let c = sqlite3_column_text(stmt, 1) else { continue }
            let value = sqlite3_column_int(stmt, 2)
            let allowed = authValued ? value >= 2 : value == 1
            out.append(TCCPermission(service: String(cString: s), client: String(cString: c), allowed: allowed))
        }
        return out
    }

    /// A friendly, human-readable label for a raw TCC service string.
    public static func friendlyService(_ raw: String) -> String {
        let trimmed = raw.hasPrefix("kTCCService") ? String(raw.dropFirst("kTCCService".count)) : raw
        switch trimmed {
        case "Camera": return "Camera"
        case "Microphone": return "Microphone"
        case "SystemPolicyAllFiles": return "Full Disk Access"
        case "SystemPolicyDesktopFolder": return "Desktop folder"
        case "SystemPolicyDocumentsFolder": return "Documents folder"
        case "SystemPolicyDownloadsFolder": return "Downloads folder"
        case "SystemPolicyNetworkVolumes": return "Network volumes"
        case "SystemPolicyRemovableVolumes": return "Removable volumes"
        case "Accessibility": return "Accessibility"
        case "PostEvent": return "Input monitoring"
        case "ListenEvent": return "Input monitoring"
        case "ScreenCapture": return "Screen recording"
        case "AppleEvents": return "Automation"
        case "Photos", "PhotosAdd": return "Photos"
        case "AddressBook": return "Contacts"
        case "Calendar": return "Calendar"
        case "Reminders": return "Reminders"
        case "Location": return "Location"
        case "MediaLibrary": return "Media library"
        case "SpeechRecognition": return "Speech recognition"
        case "Liverpool", "CoreLocation": return "Location"
        default: return trimmed
        }
    }

    /// The high-impact permissions worth flagging in an exposure map — the ones that let an
    /// app watch, listen, read everything, or drive the machine.
    public static let sensitiveServices: Set<String> = [
        "Camera", "Microphone", "ScreenCapture", "Accessibility",
        "PostEvent", "ListenEvent", "SystemPolicyAllFiles", "AppleEvents",
    ]

    public static func isSensitive(_ rawService: String) -> Bool {
        let trimmed = rawService.hasPrefix("kTCCService") ? String(rawService.dropFirst("kTCCService".count)) : rawService
        return sensitiveServices.contains(trimmed)
    }
}
