import Foundation

/// Resolves all on-disk locations Kestrel owns. The `home` is injectable so tests
/// can point everything at a temporary directory and never touch the real `~`.
public struct KestrelPaths: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    /// `~/.kestrel` — the root of everything Kestrel stores.
    public var root: URL { home.appendingPathComponent(".kestrel", isDirectory: true) }

    /// Quarantine location. Files go here before they are ever really deleted.
    public var vault: URL { root.appendingPathComponent("vault", isDirectory: true) }

    /// Append-only JSON-lines audit trail.
    public var auditLog: URL { root.appendingPathComponent("audit.log") }

    /// Daily disk-usage snapshots (used later for trends/forecasts).
    public var snapshots: URL { root.appendingPathComponent("snapshots", isDirectory: true) }
}
