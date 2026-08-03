import Foundation

/// Runs a chain of classifiers and returns the first confident verdict. Order matters:
/// put the most specific classifiers first. If nobody claims the entry, it stays
/// `.unknown` — which the planner will never schedule for removal.
public struct CompositeClassifier: Classifier {
    private let chain: [Classifier]

    public init(_ chain: [Classifier]) {
        self.chain = chain
    }

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        for classifier in chain {
            let verdict = classifier.classify(entry)
            if verdict.category != .unknown {
                return verdict
            }
        }
        return ClassifiedEntry(
            entry: entry,
            category: .unknown,
            confidence: .low,
            reason: "Unknown — skipped for safety"
        )
    }
}
