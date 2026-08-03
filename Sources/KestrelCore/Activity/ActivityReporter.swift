import Foundation

/// A roll-up of everything Kestrel has actually done, derived from the audit log.
public struct ActivitySummary: Sendable, Equatable {
    public let totalActions: Int
    public let reclaimedBytes: Int64
    public let bytesByCategory: [String: Int64]

    public init(totalActions: Int, reclaimedBytes: Int64, bytesByCategory: [String: Int64]) {
        self.totalActions = totalActions
        self.reclaimedBytes = reclaimedBytes
        self.bytesByCategory = bytesByCategory
    }
}

/// Reads the append-only audit log and summarises the real savings. Because it is built
/// from the audit trail, the numbers can never be inflated — they reflect exactly what
/// was moved to the vault and recorded.
public struct ActivityReporter {
    private let audit: AuditLog

    public init(audit: AuditLog) {
        self.audit = audit
    }

    public func summary() -> ActivitySummary {
        let entries = (try? audit.readAll()) ?? []
        let successful = entries.filter { $0.action == "vault-move" && $0.result == "ok" }
        var byCategory: [String: Int64] = [:]
        for entry in successful {
            byCategory[entry.category ?? "unknown", default: 0] += entry.bytes
        }
        return ActivitySummary(
            totalActions: successful.count,
            reclaimedBytes: successful.reduce(0) { $0 + $1.bytes },
            bytesByCategory: byCategory
        )
    }
}
