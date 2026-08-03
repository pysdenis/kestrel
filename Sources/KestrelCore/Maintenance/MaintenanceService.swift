import Foundation

/// A maintenance action macOS supports, with the exact command that performs it.
public struct MaintenanceTask: Sendable, Equatable {
    public let name: String
    public let detail: String
    public let command: String
    public let needsSudo: Bool

    public init(name: String, detail: String, command: String, needsSudo: Bool) {
        self.name = name
        self.detail = detail
        self.command = command
        self.needsSudo = needsSudo
    }
}

/// Catalog of routine maintenance actions. These change system state (and most need
/// administrator rights), so — consistent with the vault-or-nothing philosophy —
/// Kestrel presents them advisorily with the precise command rather than running them
/// behind the user's back. Execution stays an explicit, user-driven step.
public struct MaintenanceService {
    public init() {}

    public func tasks() -> [MaintenanceTask] {
        [
            MaintenanceTask(
                name: "Flush DNS cache",
                detail: "Clear resolver cache when DNS changes aren't picked up.",
                command: "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder",
                needsSudo: true
            ),
            MaintenanceTask(
                name: "Rebuild Spotlight index",
                detail: "Fix stale or missing search results.",
                command: "sudo mdutil -E /",
                needsSudo: true
            ),
            MaintenanceTask(
                name: "Rebuild Launch Services database",
                detail: "Fix duplicate or wrong 'Open With' entries.",
                command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user",
                needsSudo: false
            ),
            MaintenanceTask(
                name: "Free inactive memory",
                detail: "Return purgeable memory to the system.",
                command: "sudo purge",
                needsSudo: true
            ),
            MaintenanceTask(
                name: "Flush font caches",
                detail: "Fix garbled or missing fonts.",
                command: "atsutil databases -removeUser",
                needsSudo: false
            ),
        ]
    }
}
