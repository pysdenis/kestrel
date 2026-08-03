import Foundation

/// Classifies regenerable caches and log files under a user's `Library`. Conservative:
/// it only claims entries whose location clearly marks them as caches or logs, so app
/// support data, preferences and containers are never touched here.
public struct CacheLogClassifier: Classifier {
    public init() {}

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        let path = entry.url.path

        if path.contains("/Library/Caches/") {
            return ClassifiedEntry(entry: entry, category: .safeCache, confidence: .medium, reason: "Regenerable cache")
        }

        if path.contains("/Library/Logs/") || entry.url.pathExtension == "log" {
            return ClassifiedEntry(entry: entry, category: .logs, confidence: .medium, reason: "Log file")
        }

        return ClassifiedEntry(entry: entry, category: .unknown, confidence: .low, reason: "Not a cache or log")
    }
}
