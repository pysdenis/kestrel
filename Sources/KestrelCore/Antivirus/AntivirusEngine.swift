import Foundation

/// On-demand scanner. Walks a path, runs the signature rules over each file, and adds a
/// small honest heuristic: an executable that is still quarantined (came from the
/// internet, never cleared) is worth flagging. Nothing here invents threats — a clean
/// tree yields an empty report.
public struct AntivirusEngine {
    private let scanner: RuleScanner
    private let quarantine: QuarantineReader
    private let fm: FileManager

    public init(
        scanner: RuleScanner = RuleScanner(),
        quarantine: QuarantineReader = QuarantineReader(),
        fm: FileManager = .default
    ) {
        self.scanner = scanner
        self.quarantine = quarantine
        self.fm = fm
    }

    public func scan(root: URL) -> ScanReport {
        let files = (try? Scanner().scanFiles(under: root, pruning: [], includingHidden: true)) ?? []
        let findings = files.flatMap { scanFile($0.url) }
        return ScanReport(scanned: files.count, findings: findings)
    }

    /// Scan a single file: signature rules plus the quarantined-executable heuristic.
    /// Shared by the on-demand walk and the on-access watcher.
    public func scanFile(_ url: URL) -> [ScanFinding] {
        var findings = scanner.scanFile(url)
        if fm.isExecutableFile(atPath: url.path), let info = quarantine.read(url) {
            findings.append(ScanFinding(
                path: url.path,
                rule: "Quarantined executable",
                severity: .suspicious,
                evidence: "com.apple.quarantine" + (info.agent.map { " via \($0)" } ?? "")
            ))
        }
        return findings
    }
}
