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
        var findings: [ScanFinding] = []
        for file in files {
            findings.append(contentsOf: scanner.scanFile(file.url))
            if fm.isExecutableFile(atPath: file.url.path), let info = quarantine.read(file.url) {
                findings.append(ScanFinding(
                    path: file.url.path,
                    rule: "Quarantined executable",
                    severity: .suspicious,
                    evidence: "com.apple.quarantine" + (info.agent.map { " via \($0)" } ?? "")
                ))
            }
        }
        return ScanReport(scanned: files.count, findings: findings)
    }
}
