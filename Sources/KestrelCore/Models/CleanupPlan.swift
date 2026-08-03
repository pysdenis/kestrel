import Foundation

/// One thing the plan proposes to remove, with the reason it was selected.
public struct CleanupItem: Codable, Sendable, Equatable {
    public let entry: FileEntry
    public let category: Category
    public let reason: String

    public init(entry: FileEntry, category: Category, reason: String) {
        self.entry = entry
        self.category = category
        self.reason = reason
    }
}

/// The full proposal. Nothing here has been touched yet — a plan is inert data
/// until an `CleanupExecutor` runs it with `apply: true`.
public struct CleanupPlan: Codable, Sendable {
    public let items: [CleanupItem]

    public init(items: [CleanupItem]) {
        self.items = items
    }

    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.entry.size } }
    public var count: Int { items.count }

    /// Bytes grouped by category, for a per-category breakdown in the UI/CLI.
    public var bytesByCategory: [Category: Int64] {
        var out: [Category: Int64] = [:]
        for item in items {
            out[item.category, default: 0] += item.entry.size
        }
        return out
    }
}
