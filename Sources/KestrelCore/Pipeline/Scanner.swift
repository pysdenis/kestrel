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

    public func makeEntry(_ url: URL) -> FileEntry {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
        let isDirectory = values?.isDirectory ?? false
        let modified = values?.contentModificationDate ?? .distantPast
        let size = VaultService.entrySize(of: url, fm: fm)
        return FileEntry(url: url, size: size, modified: modified, isDirectory: isDirectory)
    }
}
