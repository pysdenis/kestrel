import Foundation

/// Finds leftover data from apps that are no longer installed: reverse-DNS-named folders
/// and preference files under `~/Library` whose owning app cannot be found in any
/// Applications directory. Apple's own data (`com.apple.*`) is always left alone, and
/// results are returned as a normal (vault-backed, undoable) cleanup plan.
public struct OrphanFinder {
    private let home: URL
    private let fm: FileManager
    private let uninstaller: AppUninstaller

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fm: FileManager = .default) {
        self.home = home
        self.fm = fm
        self.uninstaller = AppUninstaller(home: home, fm: fm)
    }

    /// Directories whose immediate children are named by bundle id.
    private var idFolderRoots: [URL] {
        ["Application Support", "Caches", "Containers", "HTTPStorages", "WebKit"]
            .map { home.appendingPathComponent("Library/\($0)") }
    }

    /// `installedBundleIds` can be injected in tests; otherwise it is read from disk.
    public func find(installedBundleIds: Set<String>? = nil) -> CleanupPlan {
        let installed = installedBundleIds ?? installedIds()
        var items: [CleanupItem] = []

        for root in idFolderRoots {
            for url in children(of: root) {
                let id = url.lastPathComponent
                guard isOrphan(id, installed: installed), !SafetyGuard.isProtected(url) else { continue }
                items.append(CleanupItem(entry: Scanner().makeEntry(url), category: .appLeftover, reason: "Orphaned data — no installed app for \(id)"))
            }
        }
        // Preferences are files named <id>.plist.
        let prefs = home.appendingPathComponent("Library/Preferences")
        for url in children(of: prefs) where url.pathExtension == "plist" {
            let id = url.deletingPathExtension().lastPathComponent
            guard isOrphan(id, installed: installed), !SafetyGuard.isProtected(url) else { continue }
            items.append(CleanupItem(entry: Scanner().makeEntry(url), category: .appLeftover, reason: "Orphaned preferences — no installed app for \(id)"))
        }

        return CleanupPlan(items: items)
    }

    // MARK: - Internals

    /// A reverse-DNS bundle id (at least two dots), not Apple's, and not installed.
    private func isOrphan(_ id: String, installed: Set<String>) -> Bool {
        guard id.filter({ $0 == "." }).count >= 2 else { return false }
        guard !id.hasPrefix("com.apple.") else { return false }
        return !installed.contains(id)
    }

    private func children(of dir: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private func installedIds() -> Set<String> {
        var ids = Set<String>()
        for dir in uninstaller.applicationDirectories {
            for app in children(of: dir) where app.pathExtension == "app" {
                if let id = uninstaller.bundleIdentifier(of: app) { ids.insert(id) }
            }
        }
        return ids
    }
}
