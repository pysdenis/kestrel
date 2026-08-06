import Foundation

/// Measures the size of a curated set of storage hogs so day-over-day snapshots can attribute
/// growth to a culprit ("Xcode DerivedData grew +12 GB"). Deliberately limited to prompt-free
/// locations under the user's own `~/Library` (plus the Trash) that actually balloon and are
/// regeneratable — so the once-a-day walk stays bounded and never triggers a TCC prompt.
public enum SpaceBreakdown {
    /// (friendly label, home-relative path). Labels double as the snapshot breakdown keys.
    public static let locations: [(label: String, path: String)] = [
        ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData"),
        ("Xcode device support", "Library/Developer/Xcode/iOS DeviceSupport"),
        ("iOS backups", "Library/Application Support/MobileSync/Backup"),
        ("Caches", "Library/Caches"),
        ("Trash", ".Trash"),
    ]

    /// The `~`-relative path for a breakdown label **only** when it's a regeneratable cache that's
    /// safe to auto-clean on a schedule (DerivedData, device support, Caches) — never Trash or iOS
    /// backups. Used to turn a regrowth cadence into a data-driven Automation rule.
    public static func autoCleanablePath(forLabel label: String) -> String? {
        let safe: Set<String> = ["Xcode DerivedData", "Xcode device support", "Caches"]
        guard safe.contains(label) else { return nil }
        return locations.first { $0.label == label }.map { "~/\($0.path)" }
    }

    public static func measure(home: URL, fm: FileManager = .default) -> [String: Int64] {
        var out: [String: Int64] = [:]
        for location in locations {
            let url = home.appendingPathComponent(location.path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let size = directorySize(url, fm: fm)
            if size > 0 { out[location.label] = size }
        }
        return out
    }

    static func directorySize(_ url: URL, fm: FileManager) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        var total: Int64 = 0
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let file as URL in enumerator {
            let v = try? file.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}
