import Foundation

/// A published Kestrel release, as read from GitHub's Releases API.
public struct ReleaseInfo: Sendable, Equatable {
    public let tag: String            // raw tag, e.g. "v0.1.1"
    public let version: String        // cleaned semver, e.g. "0.1.1"
    public let notes: String          // release body (markdown)
    public let pageURL: URL           // html_url of the release
    public let downloadURL: URL?      // first .dmg/.zip asset, if the release has one
    public let assetName: String?

    public init(tag: String, version: String, notes: String, pageURL: URL, downloadURL: URL?, assetName: String?) {
        self.tag = tag; self.version = version; self.notes = notes
        self.pageURL = pageURL; self.downloadURL = downloadURL; self.assetName = assetName
    }
}

/// Kestrel's own update check, against GitHub Releases. This is the one feature that reaches
/// the network on its own: a single read-only GET to the *public* releases API. It sends no
/// user data, no file contents, no analytics — only your IP, as any download does — and it is
/// gated behind a setting the user controls. Consistent with the zero-telemetry stance
/// (invariant #7): opt-in, disclosed, minimal.
public enum SelfUpdate {
    /// The repository releases are published to (owner/repo).
    public static let repo = "pysdenis/kestrel"

    public static func latestURL(repo: String = repo) -> URL {
        URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    }

    /// "v0.1.1" / "V0.1.1" / " 0.1.1 " → "0.1.1".
    public static func cleanTag(_ tag: String) -> String {
        var t = tag.trimmingCharacters(in: .whitespaces)
        if t.first == "v" || t.first == "V" { t.removeFirst() }
        return t
    }

    /// Semver-ish comparison on the numeric components. Returns true when `latest` is a newer
    /// version than `current` (missing components count as 0; trailing text is ignored).
    public static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            cleanTag(s).split(separator: ".").map { comp in
                Int(comp.prefix { $0.isNumber }) ?? 0
            }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Parses GitHub's `releases/latest` JSON payload into a ReleaseInfo. Pure — no network,
    /// so it's fully unit-testable. Prefers a `.dmg` asset, then `.zip`.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let htmlString = obj["html_url"] as? String,
              let page = URL(string: htmlString) else { return nil }

        let notes = (obj["body"] as? String) ?? ""
        let assets = (obj["assets"] as? [[String: Any]]) ?? []
        func firstAsset(withSuffix suffix: String) -> [String: Any]? {
            assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(suffix) == true }
        }
        let chosen = firstAsset(withSuffix: ".dmg") ?? firstAsset(withSuffix: ".zip")
        let download = (chosen?["browser_download_url"] as? String).flatMap { URL(string: $0) }

        return ReleaseInfo(tag: tag, version: cleanTag(tag), notes: notes, pageURL: page,
                           downloadURL: download, assetName: chosen?["name"] as? String)
    }

    /// Fetch and parse the latest release. Returns nil on a non-200 or unparseable response;
    /// throws only on transport errors.
    public static func latestRelease(repo: String = repo, session: URLSession = .shared) async throws -> ReleaseInfo? {
        var request = URLRequest(url: latestURL(repo: repo))
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Kestrel", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// Convenience: the latest release, but only if it is newer than `current`.
    public static func check(current: String, repo: String = repo,
                             session: URLSession = .shared) async throws -> ReleaseInfo? {
        guard let latest = try await latestRelease(repo: repo, session: session) else { return nil }
        return isNewer(latest.version, than: current) ? latest : nil
    }
}
