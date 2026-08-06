import Foundation

/// SSD wear from the NVMe SMART log — how much of the drive's rated write life is used, total bytes
/// written, and power-on hours. Advisory: it needs `smartctl` (smartmontools, `brew install
/// smartmontools`), which isn't installed by default, so when it's missing Kestrel says so honestly
/// rather than inventing a number. Read-only; never used to scare (invariant #6).
public struct DriveWear: Sendable, Equatable {
    public let available: Bool
    public let percentageUsed: Int?     // 0 = as-new, 100 = rated life consumed
    public let bytesWritten: Int64?     // total host writes (TBW)
    public let powerOnHours: Int?
    public let note: String?

    public init(available: Bool, percentageUsed: Int? = nil, bytesWritten: Int64? = nil, powerOnHours: Int? = nil, note: String? = nil) {
        self.available = available; self.percentageUsed = percentageUsed
        self.bytesWritten = bytesWritten; self.powerOnHours = powerOnHours; self.note = note
    }

    static let unavailable = DriveWear(available: false, note: "Install smartmontools (brew install smartmontools) for SSD wear stats.")

    /// Parse `smartctl -A -j <device>` JSON. NVMe data-units are 1000×512 bytes each. Pure.
    public static func parse(_ data: Data) -> DriveWear {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unavailable }
        guard let log = root["nvme_smart_health_information_log"] as? [String: Any] else {
            // Not an NVMe drive (or smartctl couldn't read it) — honest "not available".
            return DriveWear(available: false, note: "This drive doesn't report NVMe wear data.")
        }
        let used = log["percentage_used"] as? Int
        let units = (log["data_units_written"] as? Int).map { Int64($0) * 512_000 }
        let hours = log["power_on_hours"] as? Int
        return DriveWear(available: true, percentageUsed: used, bytesWritten: units, powerOnHours: hours, note: nil)
    }

    /// Best-effort read of the boot drive's wear via smartctl (needs it installed; may need sudo for
    /// some controllers, in which case it resolves to "not available" rather than prompting).
    public static func read(runner: CommandRunner = ProcessRunner()) -> DriveWear {
        guard let device = bootDevice(runner: runner) else { return .unavailable }
        guard let out = try? runner.run("smartctl", ["-A", "-j", device]), !out.isEmpty,
              let data = out.data(using: .utf8) else { return .unavailable }
        return parse(data)
    }

    /// The whole-disk device node of `/` (e.g. "/dev/disk0"), from `diskutil info /`.
    public static func bootDevice(runner: CommandRunner) -> String? {
        guard let out = try? runner.run("diskutil", ["info", "/"]) else { return nil }
        for line in out.split(separator: "\n") {
            if let r = line.range(of: "Part of Whole:") {
                let whole = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                return whole.isEmpty ? nil : "/dev/\(whole)"
            }
        }
        return nil
    }
}
