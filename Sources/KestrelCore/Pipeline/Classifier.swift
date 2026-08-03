import Foundation

/// Assigns a `Category` and `Confidence` to a `FileEntry`. Implementations must be
/// conservative: anything they are unsure about must come back as `.unknown`, which
/// the planner will never schedule for removal.
public protocol Classifier {
    func classify(_ entry: FileEntry) -> ClassifiedEntry
}

/// Default classifier for child-level scans. Composes the focused classifiers
/// (dev artifacts, then caches/logs) and returns the first confident verdict; if
/// none claims the entry it stays `.unknown`, which the planner never removes.
public struct RuleClassifier: Classifier {
    /// Directory names a deep scan should treat as single units and not descend into.
    public static var devArtifactDirs: Set<String> { DevArtifactClassifier.pruneDirectories }

    private let composite: CompositeClassifier

    public init(fm: FileManager = .default) {
        composite = CompositeClassifier([
            DevArtifactClassifier(fm: fm),
            CacheLogClassifier(),
        ])
    }

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        composite.classify(entry)
    }
}
