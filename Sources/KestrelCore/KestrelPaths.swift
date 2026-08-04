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

    /// User-defined maintenance rules (declarative, JSON).
    public var rules: URL { root.appendingPathComponent("rules.json") }

    /// Rolling per-process energy samples (for the "last 24h" battery view).
    public var energyLog: URL { root.appendingPathComponent("energy.json") }

    /// Optional Gemini API key file (GUI apps don't inherit the shell environment).
    public var geminiKey: URL { root.appendingPathComponent("gemini.key") }

    /// User allowlist — absolute paths Kestrel must never touch (fed into `SafetyGuard`).
    public var exclusions: URL { root.appendingPathComponent("exclusions.json") }
}
