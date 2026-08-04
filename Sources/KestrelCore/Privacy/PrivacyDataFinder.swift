import Foundation

/// A concrete piece of browsing-privacy data on disk — a browser cache, history store, or
/// cookie jar. Review-only: clearing history/cookies drops your history and signs you out, so
/// nothing here is ever removed unless the user picks it by name. Passwords and bookmarks are
/// never targeted.
public struct PrivacyItem: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case cache, history, cookies }

    public let app: String
    public let kind: Kind
    public let url: URL
    public let size: Int64

    public init(app: String, kind: Kind, url: URL, size: Int64) {
        self.app = app; self.kind = kind; self.url = url; self.size = size
    }

    public var id: String { url.path }
}

/// Locates known browser privacy stores directly (fast — no full-disk scan), with their sizes.
/// A focused counterpart to the Cleanup pipeline's `.privacy` category.
public struct PrivacyDataFinder {
    /// (app, kind, home-relative path). Data-driven so it's easy to audit and unit-test.
    public static let locations: [(app: String, kind: PrivacyItem.Kind, path: String)] = [
        ("Safari", .cache, "Library/Caches/com.apple.Safari"),
        ("Safari", .history, "Library/Safari/History.db"),
        ("Cookies", .cookies, "Library/Cookies"),
        ("Chrome", .cache, "Library/Caches/Google/Chrome"),
        ("Chrome", .history, "Library/Application Support/Google/Chrome/Default/History"),
        ("Chrome", .cookies, "Library/Application Support/Google/Chrome/Default/Cookies"),
        ("Brave", .cache, "Library/Application Support/BraveSoftware/Brave-Browser/Default/Cache"),
        ("Edge", .cache, "Library/Application Support/Microsoft Edge/Default/Cache"),
        ("Firefox", .cache, "Library/Caches/Firefox"),
        ("QuickLook", .cache, "Library/Caches/com.apple.QuickLook.thumbnailcache"),
    ]

    private let fm: FileManager
    public init(fm: FileManager = .default) { self.fm = fm }

    public func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [PrivacyItem] {
        Self.locations.compactMap { loc in
            let url = home.appendingPathComponent(loc.path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
            let size = isDir.boolValue ? directorySize(url) : fileSize(url)
            guard size > 0 else { return nil }
            return PrivacyItem(app: loc.app, kind: loc.kind, url: url, size: size)
        }
        .sorted { $0.size > $1.size }
    }

    private func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
    }

    private func directorySize(_ url: URL) -> Int64 {
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
