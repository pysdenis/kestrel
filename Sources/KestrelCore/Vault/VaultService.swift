import Foundation

/// A single moved item, enough to restore it exactly where it came from.
public struct VaultRecord: Codable, Sendable, Equatable {
    public let originalPath: String
    public let vaultPath: String
    public let size: Int64
    public let movedAt: Date
}

/// A cleanup session: everything moved together, undoable together.
public struct VaultSession: Codable, Sendable {
    public let id: String
    public let createdAt: Date
    public var records: [VaultRecord]

    public var totalBytes: Int64 { records.reduce(0) { $0 + $1.size } }
    public var count: Int { records.count }
}

public enum VaultError: Error, Equatable {
    case sourceMissing(String)
    case sessionMissing(String)
}

/// The result of restoring a session: what came back, what was left in place because the
/// original path is occupied, and what could not be restored (with the reason). Honest so
/// the UI can say exactly what happened instead of a silent "0".
public struct UndoOutcome: Sendable, Equatable {
    public var restored: Int
    public var skippedExisting: [String]        // original paths that already exist
    public var failed: [(path: String, reason: String)]

    public init(restored: Int = 0, skippedExisting: [String] = [], failed: [(path: String, reason: String)] = []) {
        self.restored = restored
        self.skippedExisting = skippedExisting
        self.failed = failed
    }

    public static func == (lhs: UndoOutcome, rhs: UndoOutcome) -> Bool {
        lhs.restored == rhs.restored && lhs.skippedExisting == rhs.skippedExisting
            && lhs.failed.map(\.path) == rhs.failed.map(\.path)
    }

    public var isComplete: Bool { skippedExisting.isEmpty && failed.isEmpty }
}

/// The heart of Kestrel's safety model. Nothing is ever `rm`'d directly during a
/// cleanup — items are *moved* into `~/.kestrel/vault/<session>/` with a manifest,
/// so any session can be fully undone until it is purged after the retention window.
public final class VaultService {
    public let vaultRoot: URL
    private let fm = FileManager.default

    public init(vaultRoot: URL) {
        self.vaultRoot = vaultRoot
    }

    /// Default retention before a session can be permanently purged.
    public static let defaultRetention: TimeInterval = 14 * 24 * 60 * 60

    // MARK: - Sessions

    public static func newSessionId(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    @discardableResult
    public func beginSession(id: String = VaultService.newSessionId(), createdAt: Date = Date()) throws -> String {
        let session = VaultSession(id: id, createdAt: createdAt, records: [])
        try writeManifest(session)
        return id
    }

    // MARK: - Move / undo / purge

    /// Move a file or directory into the vault under the given session.
    @discardableResult
    public func move(url: URL, session id: String) throws -> VaultRecord {
        guard fm.fileExists(atPath: url.path) else { throw VaultError.sourceMissing(url.path) }

        var manifest = try readManifest(id)
        let filesDir = sessionDir(id).appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: filesDir, withIntermediateDirectories: true)

        // Prefix with the record index to guarantee a collision-free name.
        let dest = filesDir.appendingPathComponent("\(manifest.records.count)_\(url.lastPathComponent)")
        let size = Self.entrySize(of: url, fm: fm)
        try fm.moveItem(at: url, to: dest)

        let record = VaultRecord(originalPath: url.path, vaultPath: dest.path, size: size, movedAt: Date())
        manifest.records.append(record)
        try writeManifest(manifest)
        return record
    }

    /// Restore every item in a session to its original path. Existing files at a
    /// destination are left untouched (never overwrite). The session is dropped only when
    /// everything is out of the vault; if some items are skipped or fail, the manifest is
    /// rewritten with what remains so nothing is ever lost and the user can retry.
    @discardableResult
    public func undo(session id: String) throws -> UndoOutcome {
        let manifest = try readManifest(id)
        var outcome = UndoOutcome()
        var remaining: [VaultRecord] = []

        for record in manifest.records.reversed() {
            let dest = URL(fileURLWithPath: record.originalPath)
            let src = URL(fileURLWithPath: record.vaultPath)
            if !fm.fileExists(atPath: src.path) { continue }          // already gone from vault
            if fm.fileExists(atPath: dest.path) {
                outcome.skippedExisting.append(record.originalPath)
                remaining.append(record)
                continue
            }
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: src, to: dest)
                outcome.restored += 1
            } catch {
                outcome.failed.append((path: record.originalPath, reason: (error as NSError).localizedDescription))
                remaining.append(record)
            }
        }

        if remaining.isEmpty {
            try? fm.removeItem(at: sessionDir(id))
        } else {
            var kept = manifest
            kept.records = remaining
            try writeManifest(kept)     // keep only what is still in the vault — no data loss
        }
        return outcome
    }

    /// Restore a single file (by its original path) from a session, leaving the rest of the
    /// session intact. The record is dropped from the manifest only when the move-back
    /// succeeds; the session dir is removed once it holds nothing more. Granular time-travel.
    @discardableResult
    public func restoreItem(originalPath: String, session id: String) throws -> UndoOutcome {
        let manifest = try readManifest(id)
        var outcome = UndoOutcome()
        var remaining: [VaultRecord] = []

        for record in manifest.records {
            guard record.originalPath == originalPath else { remaining.append(record); continue }
            let dest = URL(fileURLWithPath: record.originalPath)
            let src = URL(fileURLWithPath: record.vaultPath)
            if !fm.fileExists(atPath: src.path) { continue }              // already gone from vault
            if fm.fileExists(atPath: dest.path) {
                outcome.skippedExisting.append(record.originalPath); remaining.append(record); continue
            }
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: src, to: dest)
                outcome.restored += 1
            } catch {
                outcome.failed.append((path: record.originalPath, reason: (error as NSError).localizedDescription))
                remaining.append(record)
            }
        }

        if remaining.isEmpty {
            try? fm.removeItem(at: sessionDir(id))
        } else {
            var kept = manifest; kept.records = remaining
            try writeManifest(kept)
        }
        return outcome
    }

    public func listSessions() throws -> [VaultSession] {
        guard fm.fileExists(atPath: vaultRoot.path) else { return [] }
        let dirs = try fm.contentsOfDirectory(at: vaultRoot, includingPropertiesForKeys: nil)
        return dirs
            .compactMap { try? readManifest($0.lastPathComponent) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Permanently delete sessions older than `interval`. This is the only place
    /// Kestrel ever really removes user data.
    @discardableResult
    public func purge(olderThan interval: TimeInterval, now: Date = Date()) throws -> [VaultSession] {
        var purged: [VaultSession] = []
        for session in try listSessions() where now.timeIntervalSince(session.createdAt) > interval {
            try fm.removeItem(at: sessionDir(session.id))
            purged.append(session)
        }
        return purged
    }

    // MARK: - Internals

    private func sessionDir(_ id: String) -> URL {
        vaultRoot.appendingPathComponent(id, isDirectory: true)
    }

    private func manifestURL(_ id: String) -> URL {
        sessionDir(id).appendingPathComponent("manifest.json")
    }

    private func writeManifest(_ session: VaultSession) throws {
        try fm.createDirectory(at: sessionDir(session.id), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(session).write(to: manifestURL(session.id))
    }

    private func readManifest(_ id: String) throws -> VaultSession {
        let manifest = manifestURL(id)
        guard fm.fileExists(atPath: manifest.path) else { throw VaultError.sessionMissing(id) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VaultSession.self, from: Data(contentsOf: manifest))
    }

    /// Total size of a file, or the recursive size of a directory.
    static func entrySize(of url: URL, fm: FileManager) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true {
            var total: Int64 = 0
            if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
                for case let file as URL in enumerator {
                    let v = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
                }
            }
            return total
        }
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }
}
