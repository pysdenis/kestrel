import Foundation

/// Tunables for a deep scan.
public struct ScanOptions: Sendable {
    public var includeDuplicates: Bool
    public var includeLargeOld: Bool
    public var largeOld: LargeOldClassifier
    public var duplicates: DuplicateFinder

    public init(
        includeDuplicates: Bool = true,
        includeLargeOld: Bool = true,
        largeOld: LargeOldClassifier = LargeOldClassifier(),
        duplicates: DuplicateFinder = DuplicateFinder()
    ) {
        self.includeDuplicates = includeDuplicates
        self.includeLargeOld = includeLargeOld
        self.largeOld = largeOld
        self.duplicates = duplicates
    }
}

/// Orchestrates a full scan of a directory tree into `[ClassifiedEntry]`, ready for the
/// planner. It walks once, and the moment it recognises a whole-unit target — a dev
/// artifact (`node_modules`, `target`, `.venv`, …) or a cache directory — it records
/// that directory and stops descending into it. This is what makes the dev-first case
/// work: a `node_modules` buried deep in a monorepo is found and counted as one item,
/// not walked file by file. Loose files that aren't caches are gathered for the
/// whole-tree analyses (large & old, duplicates). Protected trees are never entered.
public struct ScanCoordinator {
    private let fm: FileManager
    private let dev: DevArtifactClassifier
    private let cache: CacheLogClassifier
    private let privacy: PrivacyClassifier

    public init(fm: FileManager = .default) {
        self.fm = fm
        self.dev = DevArtifactClassifier(fm: fm)
        self.cache = CacheLogClassifier()
        self.privacy = PrivacyClassifier()
    }

    /// Tool caches whose whole directory is a single reclaimable unit (matched by path
    /// suffix). Per-app caches under `~/Library/Caches` are handled separately, so each
    /// app's cache stays a distinct item.
    private static let toolCacheRoots: [(suffix: String, confidence: Confidence, reason: String)] = [
        ("/.npm/_cacache", .high, "npm package cache"),
        ("/.yarn/cache", .high, "Yarn cache"),
        ("/.yarn/berry/cache", .high, "Yarn cache"),
        ("/.pnpm-store", .medium, "pnpm store (re-downloaded on demand)"),
        ("/.gradle/caches", .high, "Gradle cache"),
        ("/.cargo/registry/cache", .high, "Cargo registry cache"),
        ("/go/pkg/mod/cache/download", .high, "Go module download cache"),
    ]

    public func scan(root: URL, options: ScanOptions = ScanOptions()) throws -> [ClassifiedEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
        ]
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]
        ) else { return [] }

        var results: [ClassifiedEntry] = []
        var looseFiles: [FileEntry] = []

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate ?? .distantPast

            if values?.isDirectory == true {
                if SafetyGuard.isProtected(url) { enumerator.skipDescendants(); continue }

                let dirEntry = FileEntry(url: url, size: 0, modified: modified, isDirectory: true)
                let verdict = dev.classify(dirEntry)
                if verdict.category == .devArtifact {
                    results.append(sized(verdict))
                    enumerator.skipDescendants()
                    continue
                }
                if let (confidence, reason) = cacheUnit(url) {
                    let entry = sizedEntry(url, modified: modified)
                    results.append(ClassifiedEntry(entry: entry, category: .safeCache, confidence: confidence, reason: reason))
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }

            guard values?.isRegularFile == true, !SafetyGuard.isProtected(url) else { continue }
            let fileEntry = FileEntry(
                url: url, size: Int64(values?.fileSize ?? 0), modified: modified, isDirectory: false
            )
            let cacheVerdict = cache.classify(fileEntry)
            if cacheVerdict.category != .unknown {
                results.append(cacheVerdict)
            } else {
                let privacyVerdict = privacy.classify(fileEntry)
                if privacyVerdict.category != .unknown {
                    results.append(privacyVerdict)
                } else {
                    looseFiles.append(fileEntry)
                }
            }
        }

        if options.includeLargeOld {
            results += looseFiles.map(options.largeOld.classify).filter { $0.category != .unknown }
        }
        if options.includeDuplicates {
            results += options.duplicates.find(in: looseFiles)
        }
        return results
    }

    // MARK: - Internals

    /// Rebuild a directory verdict with the directory's real recursive size (the walk
    /// prunes here, so its children are never enumerated for size otherwise).
    private func sized(_ verdict: ClassifiedEntry) -> ClassifiedEntry {
        let entry = sizedEntry(verdict.entry.url, modified: verdict.entry.modified)
        return ClassifiedEntry(entry: entry, category: verdict.category, confidence: verdict.confidence, reason: verdict.reason)
    }

    private func sizedEntry(_ url: URL, modified: Date) -> FileEntry {
        FileEntry(url: url, size: VaultService.entrySize(of: url, fm: fm), modified: modified, isDirectory: true)
    }

    private func cacheUnit(_ url: URL) -> (Confidence, String)? {
        if url.deletingLastPathComponent().path.hasSuffix("/Library/Caches") {
            return (.medium, "Regenerable app cache: \(url.lastPathComponent)")
        }
        for root in Self.toolCacheRoots where url.path.hasSuffix(root.suffix) {
            return (root.confidence, root.reason)
        }
        return nil
    }
}
