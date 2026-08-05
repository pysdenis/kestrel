import Foundation

/// A developer package-manager cache that's safe to clear — everything here is re-downloaded
/// or rebuilt on demand, so it's regeneratable-only (invariant #4): never source, lockfiles,
/// or config.
public struct PackageCache: Sendable, Equatable, Identifiable {
    public let tool: String
    public let url: URL
    public let size: Int64

    public init(tool: String, url: URL, size: Int64) {
        self.tool = tool
        self.url = url
        self.size = size
    }

    public var id: String { url.path }
}

/// Finds global caches of common package managers / build tools under the home directory.
/// Only well-known, regeneratable cache locations are listed — never a project's own files.
public struct PackageCacheFinder {
    /// (tool, home-relative path). Kept as data so it's easy to audit and unit-test.
    public static let candidatePaths: [(tool: String, path: String)] = [
        ("npm", ".npm/_cacache"),
        ("Yarn", "Library/Caches/Yarn"),
        ("pnpm store", "Library/pnpm/store"),
        ("pip", "Library/Caches/pip"),
        ("Homebrew", "Library/Caches/Homebrew"),
        ("CocoaPods", "Library/Caches/CocoaPods"),
        ("Gradle", ".gradle/caches"),
        ("Maven", ".m2/repository"),
        ("Cargo registry", ".cargo/registry/cache"),
        ("Go build", "Library/Caches/go-build"),
        ("Go modules", "go/pkg/mod/cache/download"),
        ("Xcode DerivedData", "Library/Developer/Xcode/DerivedData"),
        ("SwiftPM", "Library/Caches/org.swift.swiftpm"),
        ("Puppeteer", ".cache/puppeteer"),
        ("Deno", "Library/Caches/deno"),
        ("Bun", ".bun/install/cache"),
        // Xcode's biggest hogs — all regeneratable (re-created on device attach / next build).
        ("Xcode iOS DeviceSupport", "Library/Developer/Xcode/iOS DeviceSupport"),
        ("Xcode watchOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport"),
        ("Xcode tvOS DeviceSupport", "Library/Developer/Xcode/tvOS DeviceSupport"),
        ("Simulator caches", "Library/Developer/CoreSimulator/Caches"),
        ("Xcode Previews", "Library/Developer/Xcode/UserData/Previews"),
        ("Carthage", "Library/Caches/org.carthage.CarthageKit"),
        // Other common regeneratable dev caches.
        ("JetBrains caches", "Library/Caches/JetBrains"),
        ("Playwright browsers", "Library/Caches/ms-playwright"),
        ("Electron", "Library/Caches/electron"),
        ("node-gyp", ".node-gyp"),
        ("Yarn Berry", ".yarn/berry/cache"),
        ("NuGet packages", ".nuget/packages"),
        ("Composer", "Library/Caches/composer"),
    ]

    private let fm: FileManager
    public init(fm: FileManager = .default) { self.fm = fm }

    public func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [PackageCache] {
        Self.candidatePaths.compactMap { candidate in
            let url = home.appendingPathComponent(candidate.path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let size = directorySize(url)
            guard size > 0 else { return nil }
            return PackageCache(tool: candidate.tool, url: url, size: size)
        }
        .sorted { $0.size > $1.size }
    }

    /// Recursive on-disk size (allocated bytes), skipping symlinks.
    func directorySize(_ url: URL) -> Int64 {
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
