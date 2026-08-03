import Foundation

/// Securely removes a file by overwriting its contents before deleting it. This is the
/// one deliberate exception to the vault-or-nothing rule: shredding is *meant* to be
/// permanent, so it never goes to the vault. It therefore requires an explicit,
/// audited action from the caller.
///
/// Honesty note: on SSDs/APFS, wear-levelling means an in-place overwrite cannot
/// guarantee the old blocks are gone — FileVault full-disk encryption is what actually
/// protects data at rest. Kestrel does the overwrite as a best effort and says so.
public struct Shredder {
    public enum ShredError: Error, Equatable {
        case missing(String)
        case isDirectory(String)
    }

    private let audit: AuditLog?
    private let fm = FileManager.default

    public init(audit: AuditLog? = nil) {
        self.audit = audit
    }

    /// Overwrite the file's bytes in place (kept for testing / multi-pass wiping).
    public func overwrite(_ url: URL, passes: Int = 1) throws {
        guard fm.fileExists(atPath: url.path) else { throw ShredError.missing(url.path) }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        guard values.isDirectory != true else { throw ShredError.isDirectory(url.path) }
        let size = values.fileSize ?? 0

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let chunkSize = 64 * 1024
        for _ in 0..<max(1, passes) {
            try handle.seek(toOffset: 0)
            var remaining = size
            while remaining > 0 {
                let n = min(chunkSize, remaining)
                var bytes = [UInt8](repeating: 0, count: n)
                arc4random_buf(&bytes, n)
                try handle.write(contentsOf: Data(bytes))
                remaining -= n
            }
            try handle.synchronize()
        }
    }

    /// Overwrite then delete. Recurses into directories (shredding each regular file).
    public func shred(_ url: URL, passes: Int = 1) throws {
        guard fm.fileExists(atPath: url.path) else { throw ShredError.missing(url.path) }
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true

        if isDir {
            let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for child in children { try shred(child, passes: passes) }
        } else {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            try overwrite(url, passes: passes)
            try? audit?.append(AuditEntry(
                action: "shred", category: nil, paths: [url.path],
                bytes: Int64(size), result: "ok"
            ))
        }
        try fm.removeItem(at: url)
    }
}
