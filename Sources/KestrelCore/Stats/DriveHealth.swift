import Foundation

/// Read-only SMART status of the boot drive, via `diskutil info /` — an honest hardware
/// signal. Advisory: if the drive doesn't report SMART (external/virtual/Fusion), we say
/// "not supported" rather than invent reassurance. Never used to scare (invariant #6).
public struct DriveHealth: Sendable, Equatable {
    public enum Status: String, Sendable {
        case verified, failing, notSupported, unknown
    }

    public let status: Status
    /// The raw value diskutil reported, kept for display/audit.
    public let raw: String

    public init(status: Status, raw: String) {
        self.status = status
        self.raw = raw
    }

    /// Extracts the "SMART Status:" line out of `diskutil info` text output.
    public static func parse(_ output: String) -> DriveHealth {
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: "SMART Status:") else { continue }
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            let lower = value.lowercased()
            let status: Status
            if lower == "verified" {
                status = .verified
            } else if lower.contains("fail") {
                status = .failing
            } else if lower.contains("not supported") || lower.contains("not applicable") {
                status = .notSupported
            } else {
                status = .unknown
            }
            return DriveHealth(status: status, raw: value)
        }
        return DriveHealth(status: .notSupported, raw: "")
    }

    public static func read(runner: CommandRunner = ProcessRunner()) -> DriveHealth {
        let output = (try? runner.run("diskutil", ["info", "/"])) ?? ""
        return parse(output)
    }
}
