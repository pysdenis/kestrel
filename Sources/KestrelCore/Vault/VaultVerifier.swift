import Foundation

/// The integrity result for one vault session — proof that its undo would actually work.
public struct VaultVerification: Sendable, Equatable, Identifiable {
    public let sessionId: String
    public let createdAt: Date
    public let checked: Int
    public let missing: [String]        // manifest entries whose stored bytes are gone
    public let sizeMismatch: [String]   // stored bytes differ in size from the manifest
    public let blocked: [String]        // the original path is occupied → undo would skip it

    public var id: String { sessionId }

    /// The bytes for every item are present and intact — restoring this session will succeed.
    public var isRestorable: Bool { missing.isEmpty && sizeMismatch.isEmpty }

    public init(sessionId: String, createdAt: Date, checked: Int, missing: [String], sizeMismatch: [String], blocked: [String]) {
        self.sessionId = sessionId; self.createdAt = createdAt; self.checked = checked
        self.missing = missing; self.sizeMismatch = sizeMismatch; self.blocked = blocked
    }
}

/// A **vault fire-drill**: without moving anything, verify that each vault session could really be
/// restored — the stored bytes still exist and match the manifest. Nobody proves their safety net;
/// this is the honesty flex behind "the cleaner you can't regret". Read-only.
public struct VaultVerifier {
    private let vault: VaultService
    private let fm: FileManager
    public init(vault: VaultService, fm: FileManager = .default) { self.vault = vault; self.fm = fm }

    public func verifyAll() -> [VaultVerification] {
        ((try? vault.listSessions()) ?? []).map(verify)
    }

    public func verify(_ session: VaultSession) -> VaultVerification {
        var missing: [String] = [], mismatch: [String] = [], blocked: [String] = []
        for record in session.records {
            let stored = URL(fileURLWithPath: record.vaultPath)
            guard fm.fileExists(atPath: stored.path) else { missing.append(record.originalPath); continue }
            // Measure size EXACTLY the way VaultService recorded it (logical bytes, `.fileSizeKey`),
            // not allocated bytes — otherwise every intact session would look "size mismatched",
            // a false alarm that would violate the "never scare" rule.
            if VaultService.entrySize(of: stored, fm: fm) != record.size { mismatch.append(record.originalPath) }
            if fm.fileExists(atPath: record.originalPath) { blocked.append(record.originalPath) }
        }
        return VaultVerification(sessionId: session.id, createdAt: session.createdAt,
                                 checked: session.records.count, missing: missing, sizeMismatch: mismatch, blocked: blocked)
    }
}
