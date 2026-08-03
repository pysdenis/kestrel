import Foundation

/// A node in a directory-size tree. `size` is the recursive total in bytes.
public struct DirNode: Codable, Sendable, Equatable {
    public let url: URL
    public let name: String
    public let size: Int64
    public let isDirectory: Bool
    public let children: [DirNode]

    public init(url: URL, name: String, size: Int64, isDirectory: Bool, children: [DirNode]) {
        self.url = url
        self.name = name
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
    }
}

/// Builds a directory-size tree so the user can see what is taking space. Read-only.
/// The top level is measured in parallel (that is where the big directories live);
/// deeper levels recurse sequentially. Symlinks are treated as leaves so the walk can
/// never loop.
public struct DiskMap {
    private let fm: FileManager

    public init(fm: FileManager = .default) {
        self.fm = fm
    }

    /// Measure `root`, expanding directories down to `maxDepth`. Directories beyond the
    /// depth are still summed (so totals are correct) but not broken down further.
    /// Children at each level are sorted largest-first.
    /// `onProgress` (if given) is called as each top-level child finishes with
    /// (completed, total, name), so a UI can show coarse but meaningful progress while
    /// the expensive top-level directories are being measured in parallel.
    public func measure(_ root: URL, maxDepth: Int = 2, onProgress: ((Int, Int, String) -> Void)? = nil) -> DirNode {
        guard isExpandableDirectory(root) else {
            return DirNode(url: root, name: root.lastPathComponent, size: fileSize(root), isDirectory: false, children: [])
        }
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [])) ?? []

        // Parallel across the top-level children — the expensive part.
        var childNodes = [DirNode?](repeating: nil, count: entries.count)
        let lock = NSLock()
        var completed = 0
        childNodes.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: entries.count) { i in
                buffer[i] = self.node(at: entries[i], depth: maxDepth - 1)
                if let onProgress {
                    lock.lock(); completed += 1; let done = completed; lock.unlock()
                    onProgress(done, entries.count, entries[i].lastPathComponent)
                }
            }
        }
        let sorted = childNodes.compactMap { $0 }.sorted { $0.size > $1.size }
        let total = sorted.reduce(0) { $0 + $1.size }
        return DirNode(url: root, name: root.lastPathComponent, size: total, isDirectory: true, children: sorted)
    }

    // MARK: - Internals

    private func node(at url: URL, depth: Int) -> DirNode {
        guard isExpandableDirectory(url) else {
            return DirNode(url: url, name: url.lastPathComponent, size: fileSize(url), isDirectory: false, children: [])
        }
        if depth <= 0 {
            return DirNode(url: url, name: url.lastPathComponent, size: VaultService.entrySize(of: url, fm: fm), isDirectory: true, children: [])
        }
        let entries = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        let children = entries.map { node(at: $0, depth: depth - 1) }.sorted { $0.size > $1.size }
        let total = children.reduce(0) { $0 + $1.size }
        return DirNode(url: url, name: url.lastPathComponent, size: total, isDirectory: true, children: children)
    }

    /// A real directory we should descend into — not a file, and not a symlink (which
    /// would risk a cycle).
    private func isExpandableDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return 0 }
        return Int64(values?.fileSize ?? 0)
    }
}
