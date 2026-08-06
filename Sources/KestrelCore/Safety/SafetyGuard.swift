import Foundation

/// Central blacklist enforcing CLAUDE.md invariant #3: certain locations and file
/// kinds are never touched, no matter what a classifier decides. This is the last
/// line of defense — the planner runs every candidate through it, so a buggy or
/// over-eager classifier still cannot schedule a keychain, an SSH key, a `.git`
/// directory, or anything under `/System` for removal.
public enum SafetyGuard {
    /// Absolute path prefixes that are always off-limits (system + package roots).
    /// `~/Library` is intentionally *not* here — per-app caches/logs under the user's
    /// Library are legitimate cleanup targets; only the system `/Library` is protected.
    public static let protectedPrefixes: [String] = [
        "/System", "/Library", "/usr", "/bin", "/sbin",
        "/etc", "/private/etc", "/private/var/db",
    ]

    /// Path segments that mark sensitive trees anywhere in the hierarchy. Matched as
    /// a whole component so `/foo/.ssh/id_rsa` trips but `/foo/myssh/` does not.
    public static let protectedSegments: Set<String> = [
        ".git", ".svn", ".hg",
        ".ssh", ".gnupg",
        "Keychains", // ~/Library/Keychains and /Library/Keychains
    ]

    /// Exact file/directory names that must never be removed as clutter, even when a
    /// deep scan walks over them. Source lockfiles live here so dev-artifact cleanup
    /// can never take a lockfile (CLAUDE.md invariant #4).
    public static let protectedNames: Set<String> = [
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
        "Cargo.lock", "Package.resolved", "Podfile.lock",
        "poetry.lock", "Gemfile.lock", "composer.lock",
    ]

    /// Bundle/library extensions that hold irreplaceable user data.
    public static let protectedExtensions: Set<String> = [
        "keychain", "keychain-db",
        "photoslibrary", "photolibrary", "musiclibrary", "tvlibrary",
        "pem", "p12", "key",
    ]

    /// User-defined allowlist: absolute paths (and their subtrees) the user has told Kestrel
    /// to never touch. Loaded from `ExclusionStore` at launch and updated when the user edits
    /// it in Settings. Checked before everything else, so an exclusion always wins.
    ///
    /// It is written on the main actor (Settings) but read from background scan tasks, so access is
    /// lock-guarded: a torn read of a `Set` mid-mutation could otherwise momentarily fail to protect
    /// a path the user just excluded while a scan is in flight — unacceptable for a delete-files app.
    private static let exclusionsLock = NSLock()
    private static var _userExclusions: Set<String> = []
    public static var userExclusions: Set<String> {
        get { exclusionsLock.lock(); defer { exclusionsLock.unlock() }; return _userExclusions }
        set { exclusionsLock.lock(); _userExclusions = newValue; exclusionsLock.unlock() }
    }

    /// Why a path is protected, or `nil` if it is safe to consider for cleanup.
    public static func protectionReason(for url: URL) -> String? {
        let path = url.path
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        for excluded in userExclusions where path == excluded || path.hasPrefix(excluded + "/") {
            return "Excluded by you (\(excluded))"
        }
        for prefix in protectedPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return "Protected system location (\(prefix))"
        }
        if protectedNames.contains(name) {
            return "Protected file (\(name))"
        }
        if protectedExtensions.contains(ext) {
            return "Protected library/credential (.\(ext))"
        }
        let components = Set(url.pathComponents)
        for segment in protectedSegments where components.contains(segment) {
            return "Inside a protected tree (\(segment))"
        }
        return nil
    }

    public static func isProtected(_ url: URL) -> Bool {
        protectionReason(for: url) != nil
    }
}
