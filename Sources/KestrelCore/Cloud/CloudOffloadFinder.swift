import Foundation

/// Finds large files that iCloud Drive is keeping a *local* copy of, which can be offloaded
/// (evicted) to free space while staying available in the cloud. Advisory: eviction keeps
/// the file in iCloud rather than removing it, so it is delegated to `brctl` rather than
/// routed through the vault.
public struct CloudOffloadFinder {
    private let home: URL
    private let fm: FileManager

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fm: FileManager = .default) {
        self.home = home
        self.fm = fm
    }

    /// iCloud Drive's on-disk root.
    public var iCloudRoot: URL { home.appendingPathComponent("Library/Mobile Documents") }

    /// Large files under `root` (default: iCloud Drive), biggest first. `.icloud`
    /// placeholder stubs (already offloaded) are skipped.
    public func find(under root: URL? = nil, minSizeBytes: Int64 = 50 * 1024 * 1024) -> [FileEntry] {
        let base = root ?? iCloudRoot
        let files = (try? Scanner().scanFiles(under: base, pruning: [], includingHidden: true)) ?? []
        return files
            .filter { $0.size >= minSizeBytes && $0.url.pathExtension != "icloud" && !SafetyGuard.isProtected($0.url) }
            .sorted { $0.size > $1.size }
    }

    /// The command that offloads (evicts) a file's local copy, keeping it in iCloud.
    public func evictCommand(for url: URL) -> String {
        "brctl evict \"\(url.path)\""
    }
}
