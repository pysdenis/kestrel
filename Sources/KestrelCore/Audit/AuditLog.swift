import Foundation

/// One immutable line in the audit trail.
public struct AuditEntry: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let action: String
    public let category: String?
    public let paths: [String]
    public let bytes: Int64
    public let result: String
    public let sessionId: String?

    public init(
        timestamp: Date = Date(),
        action: String,
        category: String? = nil,
        paths: [String],
        bytes: Int64,
        result: String,
        sessionId: String? = nil
    ) {
        self.timestamp = timestamp
        self.action = action
        self.category = category
        self.paths = paths
        self.bytes = bytes
        self.result = result
        self.sessionId = sessionId
    }
}

/// Append-only JSON-lines log. Every destructive action Kestrel takes is recorded
/// here. It only ever appends — existing lines are never rewritten.
public final class AuditLog {
    private let url: URL
    private let fm = FileManager.default

    public init(url: URL) {
        self.url = url
    }

    public func append(_ entry: AuditEntry) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(entry)
        data.append(0x0A) // newline

        if fm.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    public func readAll() throws -> [AuditEntry] {
        guard fm.fileExists(atPath: url.path) else { return [] }
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return content
            .split(separator: "\n")
            .compactMap { try? decoder.decode(AuditEntry.self, from: Data($0.utf8)) }
    }
}
