import Foundation

/// Installs a LaunchAgent that runs `kestrel rules run --apply` on a schedule, so the
/// user's declarative rules can tidy up automatically. It stays safe because the agent
/// runs the normal pipeline — everything it removes goes to the vault and is undoable.
public struct RulesScheduler {
    public static let label = "com.pysdenis.kestrel.rules"

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

    /// The launchd job definition (kept pure so it can be unit-tested).
    public func plist(executable: String, everyHours: Int) -> [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": [executable, "rules", "run", "--apply"],
            "StartInterval": max(1, everyHours) * 3600,
            "RunAtLoad": false,
            "ProcessType": "Background",
        ]
    }

    @discardableResult
    public func writePlist(executable: String, everyHours: Int) throws -> URL {
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
