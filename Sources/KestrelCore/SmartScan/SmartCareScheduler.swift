import Foundation

/// Installs a LaunchAgent that runs a weekly **honest health pass** (`kestrel smartscan`). It is
/// read-only by design — it records a fresh snapshot and reports health, but deletes nothing on its
/// own — so the scheduled job keeps the trend/forecast and weekly digest current without ever
/// touching files unattended. (For automatic cleanup use the Rules scheduler instead.)
public struct SmartCareScheduler {
    public static let label = "com.pysdenis.kestrel.smartcare"

    private let home: URL
    private let fm: FileManager

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fm: FileManager = .default) {
        self.home = home
        self.fm = fm
    }

    public var plistURL: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    public func isInstalled() -> Bool { fm.fileExists(atPath: plistURL.path) }

    /// The launchd job definition (pure — unit-testable). Runs `snapshot` then `smartscan` so the
    /// history stays fresh; both are non-destructive.
    public func plist(executable: String, everyHours: Int = 168) -> [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": [executable, "smartscan"],
            "StartInterval": max(1, everyHours) * 3600,
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
    }

    @discardableResult
    public func writePlist(executable: String, everyHours: Int = 168) throws -> URL {
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist(executable: executable, everyHours: everyHours), format: .xml, options: 0
        )
        try fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL)
        return plistURL
    }

    public func removePlist() throws {
        if isInstalled() { try fm.removeItem(at: plistURL) }
    }
}
