import Foundation

/// Turns classifier output into a concrete `CleanupPlan`, applying the safety gates:
/// unknown items are dropped, low-confidence items are dropped, protected paths are
/// dropped, review-only categories are excluded from an "all" plan, and an optional
/// category filter narrows the result.
public struct Planner {
    public var minConfidence: Confidence

    public init(minConfidence: Confidence = .medium) {
        self.minConfidence = minConfidence
    }

    public func plan(_ classified: [ClassifiedEntry], categories: Set<Category>? = nil) -> CleanupPlan {
        var seen = Set<String>()
        let items = classified
            .filter { $0.category.isDeletableByDefault }
            .filter { $0.confidence >= minConfidence }
            .filter { !SafetyGuard.isProtected($0.entry.url) }
            .filter { passesCategoryGate($0.category, requested: categories) }
            // Never list the same path twice (a file can be both a duplicate and
            // large & old) — a second move would fail on a missing source.
            .filter { seen.insert($0.entry.url.path).inserted }
            .map { CleanupItem(entry: $0.entry, category: $0.category, reason: $0.reason) }
        return CleanupPlan(items: items)
    }

    /// A `nil` request means "clean everything safe": review-only categories
    /// (duplicates, large & old) are excluded because they are judgment calls the
    /// user must opt into by name. An explicit request includes exactly what it lists.
    private func passesCategoryGate(_ category: Category, requested: Set<Category>?) -> Bool {
        guard let requested else { return !category.requiresExplicitSelection }
        return requested.contains(category)
    }
}
