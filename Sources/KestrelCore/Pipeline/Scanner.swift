import Foundation

/// Walks the filesystem and produces `FileEntry` snapshots. Read-only — a scanner
/// never modifies anything.
public struct Scanner {
    private let fm = FileManager.default

    public init() {}

    /// Immediate children of `root`, each with a recursively computed size.
    /// Directories are returned as a single entry (so e.g. `node_modules` is one
    /// item, not thousands) — the classifier decides what to do with them.
    public func scanChildren(of root: URL) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        let children = try fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return children.map(makeEntry)
    }

    /// Recursively enumerate regular files under `root` for whole-tree analyses
    /// (duplicates, large & old). Directories whose names are in `pruning` are treated
    /// as single units and not descended into (so we never walk the thousands of files
    /// inside `node_modules`), and protected trees are skipped entirely. Read-only.
    public func scanFiles(
        under root: URL,
        pruning: Set<String> = DevArtifactClassifier.pruneDirectories,
        includingHidden: Bool = false,
        skipProtectedFiles: Bool = true
    ) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
        ]
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includingHidden { options.insert(.skipsHiddenFiles) }

        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: keys, options: options
        ) else { return [] }

        var out: [FileEntry] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if pruning.contains(url.lastPathComponent) || SafetyGuard.isProtected(url) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true, !(skipProtectedFiles && SafetyGuard.isProtected(url)) else { continue }
            out.append(FileEntry(
                url: url,
                size: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast,
                isDirectory: false
            ))
        }
        return out
    }

    public func makeEntry(_ url: URL) -> FileEntry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let isDirectory = values?.isDirectory ?? false
        let modified = values?.contentModificationDate ?? .distantPast
        let size = VaultService.entrySize(of: url, fm: fm)
        return FileEntry(url: url, size: size, modified: modified, isDirectory: isDirectory)
    }
}
