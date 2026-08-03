import Foundation

/// The state of macOS's own protections: Gatekeeper assessments and the installed
/// XProtect signature version. Read-only status — Kestrel reports it, never fakes it.
public struct GatekeeperStatus: Sendable, Equatable {
    public let assessmentsEnabled: Bool?
    public let xprotectVersion: String?

    public init(assessmentsEnabled: Bool?, xprotectVersion: String?) {
        self.assessmentsEnabled = assessmentsEnabled
        self.xprotectVersion = xprotectVersion
    }
}

public struct SystemProtectionReader {
    private let runner: CommandRunner

    public init(runner: CommandRunner = ProcessRunner()) {
        self.runner = runner
    }

    public func status() -> GatekeeperStatus {
        let output = (try? runner.run("spctl", ["--status"])) ?? ""
        let enabled: Bool?
        if output.contains("assessments enabled") { enabled = true }
        else if output.contains("assessments disabled") { enabled = false }
        else { enabled = nil }
        return GatekeeperStatus(assessmentsEnabled: enabled, xprotectVersion: Self.xprotectVersion())
    }

    static func xprotectVersion() -> String? {
        let candidates = [
            "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
            "/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist",
        ]
        for path in candidates {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let dict = obj as? [String: Any] else { continue }
            if let version = dict["CFBundleShortVersionString"] as? String { return version }
        }
        return nil
    }
}
