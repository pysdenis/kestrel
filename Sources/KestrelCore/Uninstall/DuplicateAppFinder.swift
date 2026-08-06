import Foundation

/// One copy of an application found on disk.
public struct AppCopy: Sendable, Equatable {
    public let url: URL
    public let version: String?
    public let size: Int64
    public let location: String   // human label: "Applications", "Downloads"…
    public init(url: URL, version: String?, size: Int64, location: String) {
        self.url = url; self.version = version; self.size = size; self.location = location
    }
}

/// The same app found in more than one place (or more than one version) — with the copy Kestrel
/// suggests keeping first, and the rest as reclaim candidates.
public struct DuplicateAppGroup: Sendable, Equatable, Identifiable {
    public let bundleID: String
    public let name: String
    public let copies: [AppCopy]   // sorted best-to-keep first
    public var id: String { bundleID }
    /// Bytes of the non-kept copies (what removing the extras would free).
    public var reclaimableBytes: Int64 { copies.dropFirst().reduce(0) { $0 + $1.size } }
    public init(bundleID: String, name: String, copies: [AppCopy]) {
        self.bundleID = bundleID; self.name = name; self.copies = copies
    }
}

/// Finds apps that exist in more than one location or version — a stale copy left in Downloads next
/// to the installed one, an old version beside a new. Read-only discovery; removal (elsewhere)
/// routes the extra copies through the vault, never the one it suggests keeping.
public struct DuplicateAppFinder {
    private let fm: FileManager
    public init(fm: FileManager = .default) { self.fm = fm }

    public func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [DuplicateAppGroup] {
        let roots: [(URL, String)] = [
            (URL(fileURLWithPath: "/Applications"), "Applications"),
            (home.appendingPathComponent("Applications"), "User Applications"),
            (home.appendingPathComponent("Downloads"), "Downloads"),
            (home.appendingPathComponent("Desktop"), "Desktop"),
        ]
        var byBundle: [String: [AppCopy]] = [:]
        var namesByBundle: [String: String] = [:]

        for (root, label) in roots {
            guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for app in entries where app.pathExtension == "app" {
                guard let bundle = Bundle(url: app),
                      let id = bundle.bundleIdentifier else { continue }
                let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String)
                    ?? (bundle.infoDictionary?["CFBundleVersion"] as? String)
                let size = directorySize(app)
                byBundle[id, default: []].append(AppCopy(url: app, version: version, size: size, location: label))
                namesByBundle[id] = app.deletingPathExtension().lastPathComponent
            }
        }

        return byBundle.compactMap { id, copies -> DuplicateAppGroup? in
            guard copies.count > 1 else { return nil }
            return DuplicateAppGroup(bundleID: id, name: namesByBundle[id] ?? id, copies: Self.rank(copies))
        }
        .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Order copies best-to-keep first: prefer /Applications, then a higher version, then larger.
    /// Pure — unit-testable.
    public static func rank(_ copies: [AppCopy]) -> [AppCopy] {
        copies.sorted { a, b in
            let aApps = a.location == "Applications", bApps = b.location == "Applications"
            if aApps != bApps { return aApps }
            let cmp = compareVersions(a.version, b.version)
            if cmp != 0 { return cmp > 0 }
            return a.size > b.size
        }
    }

    /// Compare dotted version strings numerically. Returns 1 if a > b, -1 if a < b, 0 if equal/unknown.
    public static func compareVersions(_ a: String?, _ b: String?) -> Int {
        guard let a, let b else { return 0 }
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y ? 1 : -1 }
        }
        return 0
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
