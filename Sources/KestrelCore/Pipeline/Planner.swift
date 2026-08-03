import Foundation

/// Turns classifier output into a concrete `CleanupPlan`, applying the safety gates:
/// unknown items are dropped, low-confidence items are dropped, and an optional
/// category filter narrows the result.
public struct Planner {
    public var minConfidence: Confidence

    public init(minConfidence: Confidence = .medium) {
        self.minConfidence = minConfidence
    }

    public func plan(_ classified: [ClassifiedEntry], categories: Set<Category>? = nil) -> CleanupPlan {
        let items = classified
            .filter { $0.category.isDeletableByDefault }
            .filter { $0.confidence >= minConfidence }
            .filter { categories == nil || categories!.contains($0.category) }
            .map { CleanupItem(entry: $0.entry, category: $0.category, reason: $0.reason) }
        return CleanupPlan(items: items)
    }
}
