import Foundation

/// Assigns a `Category` and `Confidence` to a `FileEntry`. Implementations must be
/// conservative: anything they are unsure about must come back as `.unknown`, which
/// the planner will never schedule for removal.
public protocol Classifier {
    func classify(_ entry: FileEntry) -> ClassifiedEntry
}

/// Phase 0 baseline classifier. Deliberately narrow — richer, category-specific
/// classifiers (duplicates, large/old, app leftovers) arrive in later phases.
public struct RuleClassifier: Classifier {
    /// Regenerable developer artifact directories. Never contains source or lockfiles.
    public static let devArtifactDirs: Set<String> = [
        "node_modules", "DerivedData", ".venv", "venv",
        "target", "dist", "build", ".build", ".gradle",
    ]

    public init() {}

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        let name = entry.url.lastPathComponent
        let path = entry.url.path

        if entry.isDirectory, Self.devArtifactDirs.contains(name) {
            return ClassifiedEntry(
                entry: entry,
                category: .devArtifact,
                confidence: .high,
                reason: "Regenerable build/dependency directory: \(name)"
            )
        }

        if path.contains("/Library/Caches/") {
            return ClassifiedEntry(entry: entry, category: .safeCache, confidence: .medium, reason: "Cache file")
        }

        if path.contains("/Library/Logs/") || entry.url.pathExtension == "log" {
            return ClassifiedEntry(entry: entry, category: .logs, confidence: .medium, reason: "Log file")
        }

        return ClassifiedEntry(
            entry: entry,
            category: .unknown,
            confidence: .low,
            reason: "Unknown — skipped for safety"
        )
    }
}
