import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Reclaims the space taken by a duplicate **without deleting it**, by replacing a byte-identical
/// copy with an APFS clone of the original. The clone shares the original's storage blocks
/// (copy-on-write), so the disk usage drops to a single copy while *both* paths keep working and
/// stay independent the moment either is edited. Only ever used on files already proven identical,
/// and applied atomically — the copy is never lost if a step fails, so there's no data-loss window.
public struct APFSCloner {
    public enum CloneError: Error, Equatable {
        case notSupported          // the volume can't clone (not APFS / cross-volume)
        case cloneFailed(Int32)    // clonefile() errno
        case replaceFailed(Int32)  // rename() errno
    }

    public init() {}

    /// Whether the file's volume supports fast cloning (APFS). Cross-volume clones aren't possible.
    public static func supportsCloning(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeSupportsFileCloningKey]).volumeSupportsFileCloning) ?? false
    }

    /// Replace `copy` with an APFS clone of `original`. Returns the bytes reclaimed (the copy's
    /// size, which was occupying its own blocks). Clones to a temp beside the copy, then renames
    /// over it atomically — so if anything fails, the copy is left exactly as it was.
    @discardableResult
    public func dedupe(original: URL, copy: URL) throws -> Int64 {
        guard Self.supportsCloning(at: copy), Self.supportsCloning(at: original) else { throw CloneError.notSupported }
        let reclaimed = (try? copy.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize).map(Int64.init) ?? 0

        let tmp = copy.deletingLastPathComponent().appendingPathComponent(".kestrel-clone-\(UUID().uuidString)")

        let cloneStatus = original.withUnsafeFileSystemRepresentation { src -> Int32 in
            tmp.withUnsafeFileSystemRepresentation { dst -> Int32 in
                guard let src, let dst else { return -1 }
                return clonefile(src, dst, 0)
            }
        }
        guard cloneStatus == 0 else { throw CloneError.cloneFailed(errno) }

        // Atomically swap the clone in for the copy; on failure, clean up and leave the copy intact.
        let renameStatus = tmp.withUnsafeFileSystemRepresentation { src -> Int32 in
            copy.withUnsafeFileSystemRepresentation { dst -> Int32 in
                guard let src, let dst else { return -1 }
                return rename(src, dst)
            }
        }
        guard renameStatus == 0 else {
            let e = errno
            try? FileManager.default.removeItem(at: tmp)
            throw CloneError.replaceFailed(e)
        }
        return reclaimed
    }
}
