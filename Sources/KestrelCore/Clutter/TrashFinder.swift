import Foundation

/// Finds the contents of every Trash on the Mac (the user's `~/.Trash` plus each mounted
/// volume's `.Trashes/<uid>`). "Emptying" here still routes through the vault, so even
/// clearing the Trash is undoable until the vault is purged.
public struct TrashFinder {
    private let fm: FileManager
    private let locations: [URL]

    public init(locations: [URL]? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser, fm: FileManager = .default) {
        self.fm = fm
        self.locations = locations ?? TrashFinder.defaultLocations(home: home)
    }

    static func defaultLocations(home: URL) -> [URL] {
        var out = [home.appendingPathComponent(".Trash")]
        let uid = String(getuid())
        let volumes = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: nil)) ?? []
        for volume in volumes {
            out.append(volume.appendingPathComponent(".Trashes/\(uid)"))
        }
        return out
    }

    public func find() -> CleanupPlan {
        let scanner = Scanner()
        var items: [CleanupItem] = []
        for location in locations {
            let children = (try? fm.contentsOfDirectory(at: location, includingPropertiesForKeys: nil, options: [])) ?? []
            for url in children where !SafetyGuard.isProtected(url) {
                items.append(CleanupItem(entry: scanner.makeEntry(url), category: .trash, reason: "In the Trash"))
            }
        }
        return CleanupPlan(items: items)
    }
}
