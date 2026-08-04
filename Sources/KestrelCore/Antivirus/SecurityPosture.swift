import Foundation

/// A read-only snapshot of the Mac's built-in protections. Kestrel reports these honestly and
/// never fakes or dramatizes them (invariant #6): each item is On / Off / Unknown as the system
/// actually reports it. SIP being off (common on dev machines) is stated as fact, not alarm.
public struct SecurityPosture: Sendable, Equatable {
    public enum State: String, Sendable { case on, off, unknown }

    public let fileVault: State
    public let firewall: State
    public let firewallStealth: State
    public let sip: State
    public let gatekeeper: State
    public let xprotectVersion: String?
    /// Automatic macOS update checks (on = good).
    public let automaticUpdates: State
    /// Guest login account (on = enabled = a hardening concern).
    public let guestAccount: State

    public init(fileVault: State, firewall: State, firewallStealth: State,
                sip: State, gatekeeper: State, xprotectVersion: String?,
                automaticUpdates: State = .unknown, guestAccount: State = .unknown) {
        self.fileVault = fileVault
        self.firewall = firewall
        self.firewallStealth = firewallStealth
        self.sip = sip
        self.gatekeeper = gatekeeper
        self.xprotectVersion = xprotectVersion
        self.automaticUpdates = automaticUpdates
        self.guestAccount = guestAccount
    }
}

/// Reads the protection posture via public, read-only tools (`fdesetup status`, `csrutil status`,
/// `spctl --status`) and the firewall preference plist. All advisory — nothing is changed.
public struct SecurityPostureReader {
    private let runner: CommandRunner
    private let firewallPlistPath: String

    private let updatesPlistPath: String
    private let loginwindowPlistPath: String

    public init(runner: CommandRunner = ProcessRunner(),
                firewallPlistPath: String = "/Library/Preferences/com.apple.alf.plist",
                updatesPlistPath: String = "/Library/Preferences/com.apple.SoftwareUpdate.plist",
                loginwindowPlistPath: String = "/Library/Preferences/com.apple.loginwindow.plist") {
        self.runner = runner
        self.firewallPlistPath = firewallPlistPath
        self.updatesPlistPath = updatesPlistPath
        self.loginwindowPlistPath = loginwindowPlistPath
    }

    public func read() -> SecurityPosture {
        let firewall = readFirewall()
        return SecurityPosture(
            fileVault: Self.parseFileVault((try? runner.run("fdesetup", ["status"])) ?? ""),
            firewall: firewall.state,
            firewallStealth: firewall.stealth,
            sip: Self.parseSIP((try? runner.run("csrutil", ["status"])) ?? ""),
            gatekeeper: Self.parseGatekeeper((try? runner.run("spctl", ["--status"])) ?? ""),
            xprotectVersion: SystemProtectionReader.xprotectVersion(),
            automaticUpdates: Self.parseAutomaticUpdates(plist(at: updatesPlistPath)),
            guestAccount: Self.parseGuest(plist(at: loginwindowPlistPath))
        )
    }

    /// Automatic update checks — reads `AutomaticCheckEnabled` from the SoftwareUpdate prefs.
    public static func parseAutomaticUpdates(_ plist: [String: Any]?) -> SecurityPosture.State {
        guard let plist else { return .unknown }
        if let enabled = plist["AutomaticCheckEnabled"] as? Bool { return enabled ? .on : .off }
        return .unknown
    }

    /// Guest login account — `on` means the guest account is enabled (a hardening concern).
    public static func parseGuest(_ plist: [String: Any]?) -> SecurityPosture.State {
        guard let plist else { return .unknown }
        if let enabled = plist["GuestEnabled"] as? Bool { return enabled ? .on : .off }
        return .unknown
    }

    private func plist(at path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return obj as? [String: Any]
    }

    // MARK: - Pure parsers (unit-tested)

    public static func parseFileVault(_ output: String) -> SecurityPosture.State {
        let l = output.lowercased()
        if l.contains("filevault is on") { return .on }
        if l.contains("filevault is off") { return .off }
        return .unknown
    }

    public static func parseSIP(_ output: String) -> SecurityPosture.State {
        let l = output.lowercased()
        if l.contains("status: enabled") { return .on }
        if l.contains("status: disabled") { return .off }
        return .unknown
    }

    public static func parseGatekeeper(_ output: String) -> SecurityPosture.State {
        if output.contains("assessments enabled") { return .on }
        if output.contains("assessments disabled") { return .off }
        return .unknown
    }

    /// Firewall global state: 0 = off, 1 = on, 2 = block all incoming; stealthenabled = 0/1.
    public static func firewallStates(from plist: [String: Any]?) -> (state: SecurityPosture.State, stealth: SecurityPosture.State) {
        guard let plist else { return (.unknown, .unknown) }
        let state: SecurityPosture.State
        if let g = plist["globalstate"] as? Int { state = g >= 1 ? .on : .off } else { state = .unknown }
        let stealth: SecurityPosture.State
        if let s = plist["stealthenabled"] as? Int { stealth = s >= 1 ? .on : .off } else { stealth = .unknown }
        return (state, stealth)
    }

    private func readFirewall() -> (state: SecurityPosture.State, stealth: SecurityPosture.State) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: firewallPlistPath)),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return (.unknown, .unknown) }
        return Self.firewallStates(from: dict)
    }
}
