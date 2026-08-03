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
///
/// Sizes are the *allocated* (on-disk) bytes, not the logical length. This is what makes
/// the map honest for sparse files: a Docker.raw or VM image can report a 500 GB logical
/// length while really occupying ~15 GB of disk, and only the allocated size reflects the
/// space you'd actually reclaim. Set `physical: false` for deterministic logical sizes
/// (used by tests, where block-rounding would be filesystem-dependent).
public struct DiskMap {
    private let fm: FileManager
    private let physical: Bool

    public init(fm: FileManager = .default, physical: Bool = true) {
        self.fm = fm
        self.physical = physical
    }

    /// Measure `root`, expanding directories down to `maxDepth`. Directories beyond the
    /// depth are still summed (so totals are correct) but not broken down further.
    /// Children at each level are sorted largest-first.
    ///
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
            return DirNode(url: url, name: url.lastPathComponent, size: directorySize(url), isDirectory: true, children: [])
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

    /// Size of a single file: allocated blocks (honest for sparse files) unless
    /// `physical` is off, then the logical length.
    private func fileSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return 0 }
        if physical { return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0) }
        return Int64(values?.fileSize ?? 0)
    }

    /// Recursive size of a directory beyond the expand depth — still summed so totals
    /// stay correct, using the same allocated-vs-logical rule as `fileSize`.
    private func directorySize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) {
            for case let file as URL in enumerator {
                let v = try? file.resourceValues(forKeys: Set(keys))
                guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
                if physical { total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0) }
                else { total += Int64(v?.fileSize ?? 0) }
            }
        }
        return total
    }
}
