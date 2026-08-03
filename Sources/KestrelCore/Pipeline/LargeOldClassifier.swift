import Foundation

/// Surfaces large files that have not been touched in a long time. This is a
/// review-only category (`Category.requiresExplicitSelection`): it is never part of a
/// default cleanup, because a big, old file might still be wanted (a video, an archive,
/// a disk image). It is offered as a list the user opts into with `--category large`.
///
/// Thresholds are configurable so callers can tune what counts as "large" and "old".
public struct LargeOldClassifier: Classifier {
    public let minSize: Int64
    public let minAge: TimeInterval
    private let now: Date

    public static let defaultMinSize: Int64 = 100 * 1024 * 1024   // 100 MB
    public static let defaultMinAge: TimeInterval = 180 * 24 * 60 * 60 // ~6 months

    public init(
        minSize: Int64 = LargeOldClassifier.defaultMinSize,
        minAge: TimeInterval = LargeOldClassifier.defaultMinAge,
        now: Date = Date()
    ) {
        self.minSize = minSize
        self.minAge = minAge
        self.now = now
    }

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        guard !entry.isDirectory else { return unknown(entry) }
        let age = now.timeIntervalSince(entry.modified)
        guard entry.size >= minSize, age >= minAge else { return unknown(entry) }

        let days = Int(age / (24 * 60 * 60))
        return ClassifiedEntry(
            entry: entry,
            category: .largeOld,
            confidence: .medium,
            reason: "Large (\(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))) and untouched for \(days) days"
        )
    }

    private func unknown(_ entry: FileEntry) -> ClassifiedEntry {
        ClassifiedEntry(entry: entry, category: .unknown, confidence: .low, reason: "Not large & old")
    }
}
