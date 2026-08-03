import Foundation

/// Declarative match criteria for a maintenance rule. All specified fields must hold
/// (logical AND); unset fields are ignored. Kept intentionally simple and safe.
public struct RuleCriteria: Codable, Sendable, Equatable {
    public var olderThanDays: Int?
    public var largerThanBytes: Int64?
    public var nameContains: String?
    public var extensions: [String]?

    public init(olderThanDays: Int? = nil, largerThanBytes: Int64? = nil, nameContains: String? = nil, extensions: [String]? = nil) {
        self.olderThanDays = olderThanDays
        self.largerThanBytes = largerThanBytes
        self.nameContains = nameContains
        self.extensions = extensions
    }
}

/// A named rule: which tree to look in and what to match. Actions always route through
/// the normal vault-backed pipeline — there is no shortcut around the vault.
public struct MaintenanceRule: Codable, Sendable, Equatable {
    public let name: String
    public let root: String
    public let criteria: RuleCriteria

    public init(name: String, root: String, criteria: RuleCriteria) {
        self.name = name
        self.root = root
        self.criteria = criteria
    }
}

/// Evaluates declarative rules into cleanup plans. Example: "Downloads older than 30
/// days → vault". The output is an ordinary `CleanupPlan`, so it is dry-run-previewable,
/// vault-backed and undoable like everything else. Protected paths are skipped by the
/// scanner walk.
public struct RulesEngine {
    private let now: Date

    public init(now: Date = Date()) {
        self.now = now
    }

    public func evaluate(_ rule: MaintenanceRule) -> CleanupPlan {
        let root = URL(fileURLWithPath: (rule.root as NSString).expandingTildeInPath)
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: false)) ?? []
        let items = files.compactMap { entry -> CleanupItem? in
            guard matches(entry, rule.criteria) else { return nil }
            return CleanupItem(entry: entry, category: .largeOld, reason: "Matched rule '\(rule.name)'")
        }
        return CleanupPlan(items: items)
    }

    private func matches(_ entry: FileEntry, _ criteria: RuleCriteria) -> Bool {
        if let days = criteria.olderThanDays, now.timeIntervalSince(entry.modified) < TimeInterval(days) * 86400 {
            return false
        }
        if let minBytes = criteria.largerThanBytes, entry.size < minBytes {
            return false
        }
        if let needle = criteria.nameContains,
           !entry.url.lastPathComponent.lowercased().contains(needle.lowercased()) {
            return false
        }
        if let exts = criteria.extensions,
           !exts.map({ $0.lowercased() }).contains(entry.url.pathExtension.lowercased()) {
            return false
        }
        return true
    }

    // MARK: - Persistence

    public static func load(from url: URL) -> [MaintenanceRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MaintenanceRule].self, from: data)) ?? []
    }

    public static func save(_ rules: [MaintenanceRule], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rules).write(to: url)
    }
}
