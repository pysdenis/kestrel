import Foundation

/// Classifies regenerable caches and log files. It matches only well-known cache/log
/// locations — per-app Library caches and the content caches of common developer
/// tools (npm, Yarn, pnpm, pip, Cargo, Go, Gradle, Maven, CocoaPods) — so real app
/// data (Application Support, Preferences, Containers' documents) is never claimed.
///
/// Deliberately conservative about stray `.log` files: a log that is not inside a
/// recognised logs directory is left `.unknown`, so a project's own `debug.log` is
/// never swept up.
public struct CacheLogClassifier: Classifier {
    struct Rule {
        let fragment: String
        let category: Category
        let confidence: Confidence
        let reason: String
    }

    /// Ordered; first matching fragment wins. Specific developer-tool caches come
    /// first so they get a precise reason, then the broad Library locations.
    static let rules: [Rule] = [
        // Developer tool caches (content-addressed, always re-downloadable).
        Rule(fragment: "/.npm/_cacache/", category: .safeCache, confidence: .high, reason: "npm package cache"),
        Rule(fragment: "/.npm/_logs/", category: .logs, confidence: .high, reason: "npm log"),
        Rule(fragment: "/.yarn/cache/", category: .safeCache, confidence: .high, reason: "Yarn cache"),
        Rule(fragment: "/.yarn/berry/cache/", category: .safeCache, confidence: .high, reason: "Yarn cache"),
        Rule(fragment: "/.pnpm-store/", category: .safeCache, confidence: .medium, reason: "pnpm store (re-downloaded on demand)"),
        Rule(fragment: "/.cargo/registry/cache/", category: .safeCache, confidence: .high, reason: "Cargo registry cache"),
        Rule(fragment: "/.cargo/registry/src/", category: .safeCache, confidence: .medium, reason: "Cargo extracted sources (regenerable)"),
        Rule(fragment: "/go/pkg/mod/cache/download/", category: .safeCache, confidence: .high, reason: "Go module download cache"),
        Rule(fragment: "/.gradle/caches/", category: .safeCache, confidence: .high, reason: "Gradle cache"),
        Rule(fragment: "/.m2/repository/", category: .safeCache, confidence: .medium, reason: "Maven repository cache"),
        Rule(fragment: "/Library/Caches/CocoaPods/", category: .safeCache, confidence: .high, reason: "CocoaPods cache"),
        Rule(fragment: "/Library/Caches/pip/", category: .safeCache, confidence: .high, reason: "pip cache"),
        Rule(fragment: "/Library/Caches/Homebrew/", category: .safeCache, confidence: .high, reason: "Homebrew download cache"),
        // Sandboxed app caches.
        Rule(fragment: "/Data/Library/Caches/", category: .safeCache, confidence: .medium, reason: "Sandboxed app cache"),
        // Diagnostic and crash logs.
        Rule(fragment: "/Library/Logs/DiagnosticReports/", category: .logs, confidence: .medium, reason: "Diagnostic report"),
        // Broad per-app Library locations (kept last so specific rules win first).
        Rule(fragment: "/Library/Caches/", category: .safeCache, confidence: .medium, reason: "Regenerable app cache"),
        Rule(fragment: "/Library/Logs/", category: .logs, confidence: .medium, reason: "Log file"),
    ]

    public init() {}

    public func classify(_ entry: FileEntry) -> ClassifiedEntry {
        let path = entry.url.path

        for rule in Self.rules where path.contains(rule.fragment) {
            return ClassifiedEntry(entry: entry, category: rule.category, confidence: rule.confidence, reason: rule.reason)
        }

        // A log/crash file inside a recognised logs directory but not matched above.
        let ext = entry.url.pathExtension.lowercased()
        if (ext == "log" || ext == "crash"), path.contains("/Logs/") {
            return ClassifiedEntry(entry: entry, category: .logs, confidence: .medium, reason: "Log file")
        }

        return ClassifiedEntry(entry: entry, category: .unknown, confidence: .low, reason: "Not a cache or log")
    }
}
