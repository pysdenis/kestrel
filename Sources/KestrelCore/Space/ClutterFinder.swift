import Foundation

/// Finds two common kinds of disposable clutter: old disk-image / installer packages
/// (re-downloadable) and screenshots. Both are returned as ordinary vault-backed cleanup
/// plans, so removal is undoable, and every candidate is checked against `SafetyGuard`.
public struct ClutterFinder {
    private let now: Date

    public static let installerExtensions: Set<String> = ["dmg", "pkg", "iso"]

    public init(now: Date = Date()) {
        self.now = now
    }

    /// Installer/disk-image files not modified within `olderThanDays`.
    public func oldInstallers(under root: URL, olderThanDays: Int = 30) -> CleanupPlan {
        let cutoff = TimeInterval(olderThanDays) * 86400
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: false)) ?? []
        let items = files.compactMap { entry -> CleanupItem? in
            guard Self.installerExtensions.contains(entry.url.pathExtension.lowercased()),
                  now.timeIntervalSince(entry.modified) >= cutoff,
                  !SafetyGuard.isProtected(entry.url) else { return nil }
            let days = Int(now.timeIntervalSince(entry.modified) / 86400)
            return CleanupItem(entry: entry, category: .largeOld, reason: "Old installer (.\(entry.url.pathExtension.lowercased())), \(days) days old")
        }
        return CleanupPlan(items: items)
    }

    /// Screenshot image files (macOS default naming, plus CleanShot).
    public func screenshots(under root: URL) -> CleanupPlan {
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: false)) ?? []
        let items = files.compactMap { entry -> CleanupItem? in
            let name = entry.url.lastPathComponent
            guard Self.isScreenshot(name), !SafetyGuard.isProtected(entry.url) else { return nil }
            return CleanupItem(entry: entry, category: .largeOld, reason: "Screenshot")
        }
        return CleanupPlan(items: items)
    }

    static func isScreenshot(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg"].contains(ext) else { return false }
        let lower = name.lowercased()
        return lower.hasPrefix("screenshot ") || lower.hasPrefix("screen shot ") || lower.hasPrefix("cleanshot")
    }

    /// Old files sitting in Downloads (one-time-use clutter). Review-only.
    public func oldDownloads(under root: URL, olderThanDays: Int = 30) -> CleanupPlan {
        let cutoff = TimeInterval(olderThanDays) * 86400
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: false)) ?? []
        let items = files.compactMap { entry -> CleanupItem? in
            guard now.timeIntervalSince(entry.modified) >= cutoff, !SafetyGuard.isProtected(entry.url) else { return nil }
            let days = Int(now.timeIntervalSince(entry.modified) / 86400)
            return CleanupItem(entry: entry, category: .largeOld, reason: "Download, \(days) days old")
        }
        return CleanupPlan(items: items)
    }

    /// The `limit` largest individual files under `root` that are at least `minBytes` — a fast way
    /// to find single space hogs without drilling the treemap. Review-only (category `.largeOld`),
    /// vault-backed, and every candidate is checked against `SafetyGuard`, so a big file is only
    /// ever *offered*, never swept automatically. Read-only discovery.
    public func largestFiles(under root: URL, minBytes: Int64 = 100_000_000, limit: Int = 40) -> CleanupPlan {
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: false)) ?? []
        let big = files
            .filter { !$0.isDirectory && $0.size >= minBytes && !SafetyGuard.isProtected($0.url) }
            .sorted { $0.size > $1.size }
            .prefix(limit)
        let items = big.map { entry -> CleanupItem in
            let sizeText = ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
            let days = Int(now.timeIntervalSince(entry.modified) / 86400)
            return CleanupItem(entry: entry, category: .largeOld, reason: "Large file — \(sizeText), \(days) days old")
        }
        return CleanupPlan(items: Array(items))
    }

    /// Attachments received in Messages (`~/Library/Messages/Attachments/…`) — frequently large.
    /// Review-only and vault-backed (undoable). Unlike Mail these may not re-download unless
    /// Messages in iCloud is on, so the reason stays neutral and nothing is preselected.
    public func messagesAttachments(under root: URL) -> CleanupPlan {
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: true)) ?? []
        let items = files.compactMap { entry -> CleanupItem? in
            guard !entry.isDirectory, entry.size > 0, !SafetyGuard.isProtected(entry.url) else { return nil }
            return CleanupItem(entry: entry, category: .largeOld, reason: "Messages attachment")
        }
        return CleanupPlan(items: items)
    }

    /// Locally cached Mail attachments (`~/Library/Mail/.../Attachments/…`). They are
    /// re-downloadable from the server, so removing them frees space safely. Review-only.
    public func mailAttachments(under mailRoot: URL) -> CleanupPlan {
        let files = (try? Scanner().scanFiles(under: mailRoot, pruning: [], includingHidden: true)) ?? []
        let items = files.compactMap { entry -> CleanupItem? in
            guard entry.url.path.contains("/Attachments/"), !SafetyGuard.isProtected(entry.url) else { return nil }
            return CleanupItem(entry: entry, category: .largeOld, reason: "Mail attachment (re-downloadable)")
        }
        return CleanupPlan(items: items)
    }
}
