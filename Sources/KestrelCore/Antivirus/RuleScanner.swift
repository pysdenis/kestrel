import Foundation
import CryptoKit

/// A signature rule: a substring to find, or an exact file SHA-256 to match.
public struct SignatureRule: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case contains(String)
        case sha256(String)
    }
    public let name: String
    public let severity: ThreatSeverity
    public let kind: Kind

    public init(name: String, severity: ThreatSeverity, kind: Kind) {
        self.name = name
        self.severity = severity
        self.kind = kind
    }
}

/// A minimal, honest content scanner. It ships with the industry-standard EICAR test
/// signature — the file every antivirus is supposed to detect — so detection can be
/// proven to work, and it accepts additional string/hash rules. It reports only real
/// matches; a file that matches nothing produces no findings.
public struct RuleScanner {
    /// The 68-byte EICAR anti-malware test string (harmless; used to verify scanners).
    public static let eicarSignature =
        #"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"#

    public static let defaultRules: [SignatureRule] = [
        SignatureRule(name: "EICAR-STANDARD-ANTIVIRUS-TEST-FILE", severity: .malicious, kind: .contains(eicarSignature)),
    ]

    /// Skip content scanning of files larger than this (they are unlikely signature hits
    /// and reading them whole is wasteful). Hash rules still apply via streaming.
    public let maxContentBytes: Int
    public let rules: [SignatureRule]

    public init(rules: [SignatureRule] = RuleScanner.defaultRules, maxContentBytes: Int = 32 * 1024 * 1024) {
        self.rules = rules
        self.maxContentBytes = maxContentBytes
    }

    public func scanFile(_ url: URL) -> [ScanFinding] {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var findings: [ScanFinding] = []

        let containsRules = rules.compactMap { rule -> (String, ThreatSeverity, Data)? in
            if case let .contains(needle) = rule.kind { return (rule.name, rule.severity, Data(needle.utf8)) }
            return nil
        }
        if !containsRules.isEmpty, size <= maxContentBytes, let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
            for (name, severity, needle) in containsRules where data.range(of: needle) != nil {
                findings.append(ScanFinding(path: url.path, rule: name, severity: severity, evidence: "signature match"))
            }
        }

        let hashRules = rules.filter { if case .sha256 = $0.kind { return true } else { return false } }
        if !hashRules.isEmpty, let digest = sha256(url) {
            for rule in hashRules {
                if case let .sha256(hex) = rule.kind, hex.lowercased() == digest {
                    findings.append(ScanFinding(path: url.path, rule: rule.name, severity: rule.severity, evidence: "sha256:\(digest.prefix(12))…"))
                }
            }
        }
        return findings
    }

    private func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
