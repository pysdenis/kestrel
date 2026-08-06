import Foundation

/// A git repository and how much space its `.git` history is taking. Advisory only — `.git` is a
/// SafetyGuard-protected location Kestrel never touches; a bloated history is fixed by the user
/// running `git gc`, not by deletion.
public struct GitRepoInfo: Sendable, Equatable, Identifiable {
    public let path: String        // repo root
    public let name: String
    public let gitDirBytes: Int64   // size of the .git directory
    public var id: String { path }
    /// The exact command the user can run to compact this repo's history.
    public var gcCommand: String { "git -C \"\(path)\" gc --aggressive --prune=now" }

    public init(path: String, name: String, gitDirBytes: Int64) {
        self.path = path; self.name = name; self.gitDirBytes = gitDirBytes
    }
}

/// Finds git repos whose `.git` directory has grown large (bloated history, big packed objects) so
/// the user can `git gc` them. Read-only; never descends into a repo it found (so node_modules and
/// nested checkouts don't slow the walk).
public struct GitRepoAuditor {
    private let fm: FileManager
    public init(fm: FileManager = .default) { self.fm = fm }

    public func scan(root: URL, minGitBytes: Int64 = 100_000_000) -> [GitRepoInfo] {
        var out: [GitRepoInfo] = []
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        for case let dir as URL in en {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let gitDir = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: gitDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // Found a repo root: measure .git and don't descend further into this tree.
            en.skipDescendants()
            let size = directorySize(gitDir)
            if size >= minGitBytes {
                out.append(GitRepoInfo(path: dir.path, name: dir.lastPathComponent, gitDirBytes: size))
            }
        }
        return out.sorted { $0.gitDirBytes > $1.gitDirBytes }
    }

    func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        var total: Int64 = 0
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let file as URL in en {
            let v = try? file.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}
