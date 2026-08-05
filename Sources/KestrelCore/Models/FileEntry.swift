import Foundation

/// A single item discovered on disk. Immutable snapshot taken at scan time.
public struct FileEntry: Codable, Sendable, Equatable {
    public let url: URL
    /// Total size in bytes (recursive for directories).
    public let size: Int64
    public let modified: Date
    public let isDirectory: Bool

    public init(url: URL, size: Int64, modified: Date, isDirectory: Bool) {
        self.url = url
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
    }
}

/// How confident the classifier is about a category. Higher = safer to act on.
public enum Confidence: Int, Codable, Sendable, Comparable {
    case low = 1
    case medium = 2
    case high = 3

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What kind of clutter an entry is. `unknown` is never deleted by default.
public enum Category: String, Codable, Sendable, CaseIterable {
    case safeCache
    case logs
    case devArtifact
    case duplicate
    case largeOld
    case appLeftover
    case privacy
    case trash
    case unknown

    /// Safety gate: unknown items are never part of a default cleanup plan.
    public var isDeletableByDefault: Bool {
        self != .unknown
    }

    /// Categories that are surfaced for review but never swept into an "all" cleanup —
    /// the user must name them explicitly. Duplicates (which copy is the "original"?)
    /// and large & old files (that big video might be wanted) are inherently judgment
    /// calls, so removing them is always an opt-in decision.
    public var requiresExplicitSelection: Bool {
        self == .duplicate || self == .largeOld || self == .privacy
    }

    /// Regenerable, low-risk categories that a one-tap "reclaim the safe stuff" may pre-select:
    /// caches, logs, build artifacts, trash, and leftover data of already-removed apps. Excludes
    /// the judgment-call categories (duplicates, large & old, privacy) and unknowns. Still moves
    /// to the vault — "safe" means low-regret, not unrecoverable.
    public var isClearlySafe: Bool {
        switch self {
        case .safeCache, .logs, .devArtifact, .trash, .appLeftover: return true
        case .duplicate, .largeOld, .privacy, .unknown: return false
        }
    }
}

/// A `FileEntry` plus the classifier's verdict and human-readable justification.
public struct ClassifiedEntry: Codable, Sendable, Equatable {
    public let entry: FileEntry
    public let category: Category
    public let confidence: Confidence
    public let reason: String

    public init(entry: FileEntry, category: Category, confidence: Confidence, reason: String) {
        self.entry = entry
        self.category = category
        self.confidence = confidence
        self.reason = reason
    }
}
