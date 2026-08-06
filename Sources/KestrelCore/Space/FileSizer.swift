import Foundation

/// Shared on-disk size measurement, so every finder computes size the same way (allocated bytes,
/// symlinks skipped) instead of copy-pasting the same loop. Allocated size — not logical length —
/// so sparse files (Docker.raw, VM images) report their true footprint.
public enum FileSizer {
    static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey,
    ]

    /// Recursive allocated size of a file or directory. A single regular file returns its own size;
    /// a directory sums its regular-file descendants (skipping symlinks). Returns 0 on error.
    public static func size(of url: URL, fm: FileManager = .default) -> Int64 {
        let values = try? url.resourceValues(forKeys: Set(keys))
        if values?.isDirectory != true {
            guard values?.isSymbolicLink != true else { return 0 }
            return allocated(values)
        }
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let file as URL in enumerator {
            let v = try? file.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
            total += allocated(v)
        }
        return total
    }

    private static func allocated(_ v: URLResourceValues?) -> Int64 {
        Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
    }
}
