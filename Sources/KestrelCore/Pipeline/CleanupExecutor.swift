import Foundation

/// Outcome of running a plan. In a dry run nothing is moved and `sessionId` is nil.
public struct ExecutionResult: Sendable {
    public let dryRun: Bool
    public let sessionId: String?
    public let movedCount: Int
    public let movedBytes: Int64
    public let failures: [(path: String, error: String)]
    public let plan: CleanupPlan
}

/// Runs a `CleanupPlan`. Defaults to a dry run: the caller must explicitly pass
/// `apply: true` for anything to actually move. Even then, items go to the vault
/// (never `rm`) and every move is written to the audit log.
public final class CleanupExecutor {
    private let vault: VaultService
    private let audit: AuditLog

    public init(vault: VaultService, audit: AuditLog) {
        self.vault = vault
        self.audit = audit
    }

    public func execute(_ plan: CleanupPlan, apply: Bool) throws -> ExecutionResult {
        guard apply else {
            return ExecutionResult(
                dryRun: true, sessionId: nil,
                movedCount: 0, movedBytes: 0, failures: [], plan: plan
            )
        }

        let session = try vault.beginSession()
        var movedCount = 0
        var movedBytes: Int64 = 0
        var failures: [(String, String)] = []

        for item in plan.items {
            do {
                let record = try vault.move(url: item.entry.url, session: session)
                movedCount += 1
                movedBytes += record.size
                try audit.append(AuditEntry(
                    action: "vault-move",
                    category: item.category.rawValue,
                    paths: [record.originalPath],
                    bytes: record.size,
                    result: "ok",
                    sessionId: session
                ))
            } catch {
                failures.append((item.entry.url.path, "\(error)"))
                try? audit.append(AuditEntry(
                    action: "vault-move",
                    category: item.category.rawValue,
                    paths: [item.entry.url.path],
                    bytes: item.entry.size,
                    result: "error: \(error)",
                    sessionId: session
                ))
            }
        }

        return ExecutionResult(
            dryRun: false, sessionId: session,
            movedCount: movedCount, movedBytes: movedBytes,
            failures: failures, plan: plan
        )
    }
}
