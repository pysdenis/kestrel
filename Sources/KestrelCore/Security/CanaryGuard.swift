import Foundation
import CryptoKit
import CoreServices

/// One planted decoy file and the baseline it was planted with.
public struct CanaryFile: Codable, Sendable, Equatable {
    public let path: String
    public let sha256: String
    public let size: Int64
    public let plantedAt: Date
    public init(path: String, sha256: String, size: Int64, plantedAt: Date) {
        self.path = path; self.sha256 = sha256; self.size = size; self.plantedAt = plantedAt
    }
}

/// A tripped canary — one decoy that changed since it was planted.
public struct CanaryAlert: Sendable, Equatable {
    public enum Kind: String, Sendable { case modified, deleted }
    public let path: String
    public let kind: Kind
    public init(path: String, kind: Kind) { self.path = path; self.kind = kind }
}

/// The result of verifying every planted canary.
public struct CanaryReport: Sendable, Equatable {
    public let checked: Int
    public let alerts: [CanaryAlert]
    public init(checked: Int, alerts: [CanaryAlert]) { self.checked = checked; self.alerts = alerts }
    /// True when something modified or removed a decoy — a possible ransomware/mass-encryption event.
    public var isTripped: Bool { !alerts.isEmpty }
}

/// A **ransomware canary**: Kestrel plants clearly-labeled decoy files in the folders that
/// encrypting malware targets first (Documents, Desktop, Pictures) and records each decoy's
/// baseline SHA-256. If anything later rewrites or deletes a decoy, `verify()` reports it — a
/// strong early warning that files are being tampered with en masse.
///
/// Honest and non-destructive by construction: Kestrel only ever touches **its own** decoy files
/// (never user data), and this is pure **detection** — it raises an alert, it never quarantines,
/// deletes, or "fixes" anything on its own. Consistent with the "never scare" rule, a clean check
/// produces no alert at all.
public struct CanaryGuard: Sendable {
    /// The decoy's on-disk name — deliberately explicit so a user who stumbles on it understands
    /// what it is and leaves it alone. (Encrypting malware ignores the name and hits it anyway.)
    public static let decoyName = "Kestrel-Canary-DO-NOT-EDIT.txt"
    static let decoyBody = """
    This file is a Kestrel ransomware canary. Please do not edit, rename, or delete it.
    Kestrel watches it: if its contents change unexpectedly, that can mean something is
    encrypting your files, and Kestrel will warn you so you can react quickly.
    """

    private let manifestURL: URL
    public init(manifestURL: URL) { self.manifestURL = manifestURL }

    /// The folders worth protecting by default — the ones ransomware encrypts first.
    public static func defaultDirectories(home: URL) -> [URL] {
        ["Documents", "Desktop", "Pictures"].map { home.appendingPathComponent($0, isDirectory: true) }
    }

    /// Plant a decoy in each existing directory and record the manifest. Replaces any prior set.
    @discardableResult
    public func plant(in directories: [URL]) throws -> [CanaryFile] {
        let data = Data(Self.decoyBody.utf8)
        let hash = Self.hash(data)
        var planted: [CanaryFile] = []
        for dir in directories {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let url = dir.appendingPathComponent(Self.decoyName)
            try data.write(to: url)
            planted.append(CanaryFile(path: url.path, sha256: hash, size: Int64(data.count), plantedAt: Date()))
        }
        try save(planted)
        return planted
    }

    /// Re-hash every planted decoy and report any that were modified or removed.
    public func verify() -> CanaryReport {
        let files = plantedFiles()
        var alerts: [CanaryAlert] = []
        for file in files {
            let url = URL(fileURLWithPath: file.path)
            guard let data = try? Data(contentsOf: url) else {
                alerts.append(CanaryAlert(path: file.path, kind: .deleted)); continue
            }
            if Self.hash(data) != file.sha256 {
                alerts.append(CanaryAlert(path: file.path, kind: .modified))
            }
        }
        return CanaryReport(checked: files.count, alerts: alerts)
    }

    public func plantedFiles() -> [CanaryFile] { (try? load()) ?? [] }

    public var isArmed: Bool { !plantedFiles().isEmpty }

    /// Stop protecting: remove the decoys and the manifest. These are Kestrel's own throwaway
    /// files (not user data), so they are removed directly rather than routed through the vault.
    public func disarm() {
        for file in plantedFiles() { try? FileManager.default.removeItem(at: URL(fileURLWithPath: file.path)) }
        try? FileManager.default.removeItem(at: manifestURL)
    }

    // MARK: - Persistence

    private func save(_ files: [CanaryFile]) throws {
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(files).write(to: manifestURL, options: .atomic)
    }

    private func load() throws -> [CanaryFile] {
        let data = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CanaryFile].self, from: data)
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Real-time watcher: re-verifies the canaries whenever anything changes in a protected folder,
/// so a mass-encryption event trips within a fraction of a second. Detection only — on a trip it
/// calls `onTrip`; a clean change produces nothing.
///
/// Not covered by the unit runner (it depends on live FSEvents + a run loop); it is exercised
/// end-to-end through the app and `kestrel canary watch`.
public final class CanaryWatcher {
    private let guardService: CanaryGuard
    private let onTrip: (CanaryReport) -> Void
    private let watched: [String]
    private let queue = DispatchQueue(label: "com.pysdenis.kestrel.canary")
    private var stream: FSEventStreamRef?

    public init(guardService: CanaryGuard, onTrip: @escaping (CanaryReport) -> Void) {
        self.guardService = guardService
        self.onTrip = onTrip
        // Watch each decoy's parent folder — that's where an encryptor's writes land.
        self.watched = Array(Set(guardService.plantedFiles().map { URL(fileURLWithPath: $0.path).deletingLastPathComponent().path }))
    }

    public func start() {
        guard stream == nil, !watched.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<CanaryWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.recheck()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault, callback, &context, watched as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func recheck() {
        let report = guardService.verify()
        if report.isTripped { onTrip(report) }
    }
}
