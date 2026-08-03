import Foundation

/// Uninstalls an application and its leftovers by moving the bundle plus the support
/// files it scattered across `~/Library` into the vault (never `rm`). A user who runs
/// this has explicitly chosen the target, so the bundle in `/Applications` is allowed —
/// but Apple's system apps under `/System` are refused, and each leftover still passes
/// through `SafetyGuard`, so a keychain or credential can never be swept up by mistake.
public struct AppUninstaller {
    public enum UninstallError: Error, Equatable {
        case notAnApp(String)
        case missing(String)
        case systemApp(String)
        case notFound(String)
    }

    private let home: URL
    private let fm: FileManager

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fm: FileManager = .default) {
        self.home = home
        self.fm = fm
    }

    /// Standard directories an app is searched for when given a bare name.
    public var applicationDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications"),
        ]
    }

    /// Resolve a bundle path or a bare app name (`"Slack"` / `"Slack.app"`) to a `.app`.
    public func resolve(_ nameOrPath: String) throws -> URL {
        let expanded = (nameOrPath as NSString).expandingTildeInPath
        if expanded.contains("/") {
            let url = URL(fileURLWithPath: expanded)
            guard url.pathExtension == "app" else { throw UninstallError.notAnApp(expanded) }
            guard fm.fileExists(atPath: url.path) else { throw UninstallError.missing(expanded) }
            return url
        }
        let appName = nameOrPath.hasSuffix(".app") ? nameOrPath : nameOrPath + ".app"
        for dir in applicationDirectories {
            let candidate = dir.appendingPathComponent(appName)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        throw UninstallError.notFound(nameOrPath)
    }

    /// Read `CFBundleIdentifier` from the app's `Info.plist`.
    public func bundleIdentifier(of appURL: URL) -> String? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    /// The bundle plus every leftover that actually exists on disk, as a cleanup plan.
    public func plan(for appURL: URL) throws -> CleanupPlan {
        guard appURL.pathExtension == "app" else { throw UninstallError.notAnApp(appURL.path) }
        guard !appURL.path.hasPrefix("/System/") else { throw UninstallError.systemApp(appURL.path) }
        guard fm.fileExists(atPath: appURL.path) else { throw UninstallError.missing(appURL.path) }

        let bundleId = bundleIdentifier(of: appURL)
        let appName = appURL.deletingPathExtension().lastPathComponent

        var items: [CleanupItem] = [
            CleanupItem(entry: sizedEntry(appURL), category: .appLeftover, reason: "Application bundle")
        ]
        for (url, reason) in leftoverCandidates(bundleId: bundleId, appName: appName)
        where fm.fileExists(atPath: url.path) && !SafetyGuard.isProtected(url) {
            items.append(CleanupItem(entry: sizedEntry(url), category: .appLeftover, reason: reason))
        }
        return CleanupPlan(items: dedupe(items))
    }

    // MARK: - Internals

    private func leftoverCandidates(bundleId: String?, appName: String) -> [(URL, String)] {
        let lib = home.appendingPathComponent("Library")
        var out: [(URL, String)] = []
        func add(_ relative: String, _ reason: String) {
            out.append((lib.appendingPathComponent(relative), reason))
        }

        if let id = bundleId {
            add("Application Support/\(id)", "Support data (\(id))")
            add("Caches/\(id)", "Cache (\(id))")
            add("Preferences/\(id).plist", "Preferences (\(id))")
            add("Containers/\(id)", "Sandbox container (\(id))")
            add("Group Containers/\(id)", "Group container (\(id))")
            add("Saved Application State/\(id).savedState", "Saved window state")
            add("HTTPStorages/\(id)", "HTTP storage")
            add("WebKit/\(id)", "WebKit data")
            add("Cookies/\(id).binarycookies", "Cookies")
            add("Logs/\(id)", "Logs (\(id))")
            out.append(contentsOf: launchAgents(matching: id))
        }
        // Name-based fallbacks (some apps use their display name, not the bundle id).
        add("Application Support/\(appName)", "Support data (\(appName))")
        add("Logs/\(appName)", "Logs (\(appName))")
        return out
    }

    /// LaunchAgents whose filename contains the bundle id (login items / helpers).
    private func launchAgents(matching id: String) -> [(URL, String)] {
        let agentsDir = home.appendingPathComponent("Library/LaunchAgents")
        guard let entries = try? fm.contentsOfDirectory(at: agentsDir, includingPropertiesForKeys: nil) else { return [] }
        return entries
            .filter { $0.pathExtension == "plist" && $0.lastPathComponent.contains(id) }
            .map { ($0, "Launch agent (\($0.lastPathComponent))") }
    }

    private func sizedEntry(_ url: URL) -> FileEntry {
        Scanner().makeEntry(url)
    }

    private func dedupe(_ items: [CleanupItem]) -> [CleanupItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.entry.url.path).inserted }
    }
}
