import Foundation

public enum ThreatSeverity: String, Codable, Sendable, Comparable {
    case info, suspicious, malicious

    private var rank: Int { self == .malicious ? 2 : (self == .suspicious ? 1 : 0) }
    public static func < (lhs: ThreatSeverity, rhs: ThreatSeverity) -> Bool { lhs.rank < rhs.rank }
}

/// A single concrete finding, always backed by evidence (a rule name, a hash, an
/// extended attribute). Never speculative — the honesty invariant (CLAUDE.md #6) means
/// a finding must point at something real.
public struct ScanFinding: Codable, Sendable, Equatable {
    public let path: String
    public let rule: String
    public let severity: ThreatSeverity
    public let evidence: String

    public init(path: String, rule: String, severity: ThreatSeverity, evidence: String) {
        self.path = path
        self.rule = rule
        self.severity = severity
        self.evidence = evidence
    }
}

/// The result of a scan. When `findings` is empty the answer is simply "clean" — no
/// invented "recommended deep scans", no scare tactics.
public struct ScanReport: Sendable, Equatable {
    public let scanned: Int
    public let findings: [ScanFinding]

    public init(scanned: Int, findings: [ScanFinding]) {
        self.scanned = scanned
        self.findings = findings.sorted { $0.severity > $1.severity }
    }

    public var isClean: Bool { findings.isEmpty }
}
