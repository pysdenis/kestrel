import Foundation

/// A file carrying macOS's `com.apple.quarantine` attribute — i.e. something that came
/// from the internet and has not been cleared by Gatekeeper.
public struct QuarantineInfo: Sendable, Equatable {
    public let path: String
    public let agent: String?
    public let raw: String

    public init(path: String, agent: String?, raw: String) {
        self.path = path
        self.agent = agent
        self.raw = raw
    }
}

/// Reads the `com.apple.quarantine` extended attribute. The value is
/// `flags;timestamp;agent;uuid` — the agent (Safari, Chrome, curl…) tells you what
/// downloaded the file.
public struct QuarantineReader {
    public static let attribute = "com.apple.quarantine"

    public init() {}

    public func read(_ url: URL) -> QuarantineInfo? {
        guard let raw = Self.extendedAttribute(Self.attribute, path: url.path) else { return nil }
        let fields = raw.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        let agent = fields.count >= 3 ? fields[2] : nil
        return QuarantineInfo(path: url.path, agent: agent?.isEmpty == true ? nil : agent, raw: raw)
    }

    /// Top-level items under `root` that still carry the quarantine flag — i.e. things that
    /// came from the internet and haven't been cleared. Not recursive (the useful view is
    /// what's sitting in Downloads), read-only, capped.
    public func scan(root: URL, limit: Int = 200, fm: FileManager = .default) -> [QuarantineInfo] {
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return entries.compactMap { read($0) }.prefix(limit).map { $0 }
    }

    static func extendedAttribute(_ name: String, path: String) -> String? {
        let length = getxattr(path, name, nil, 0, 0, 0)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, length, 0, 0) }
        guard read >= 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
