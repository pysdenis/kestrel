import Foundation

/// One local iOS/iPadOS device backup under `MobileSync/Backup`. These are frequently the single
/// largest reclaimable item on a Mac, but they can also be the user's ONLY backup — so Kestrel
/// only ever lists them (oldest first) and lets the user decide; removal goes through the vault.
public struct DeviceBackup: Sendable, Equatable, Identifiable {
    public let udid: String
    public let deviceName: String
    public let productType: String?   // e.g. "iPhone14,2"
    public let lastBackup: Date?
    public let size: Int64
    public let path: String

    public var id: String { udid }

    public init(udid: String, deviceName: String, productType: String?, lastBackup: Date?, size: Int64, path: String) {
        self.udid = udid; self.deviceName = deviceName; self.productType = productType
        self.lastBackup = lastBackup; self.size = size; self.path = path
    }
}

/// Enumerates local device backups and reads each one's metadata from its `Info.plist`. Read-only.
/// Needs Full Disk Access to see the backup folder.
public struct DeviceBackupFinder {
    private let fm: FileManager
    public init(fm: FileManager = .default) { self.fm = fm }

    public static func backupRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
    }

    /// Every backup found, sorted oldest-last-backup first (the safest removal candidates on top).
    public func find(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [DeviceBackup] {
        let root = Self.backupRoot(home: home)
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var out: [DeviceBackup] = []
        for dir in entries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let info = Self.readInfo(dir.appendingPathComponent("Info.plist"), fm: fm)
            let size = FileSizer.size(of: dir)
            guard size > 0 else { continue }
            out.append(DeviceBackup(udid: dir.lastPathComponent,
                                    deviceName: info.name ?? dir.lastPathComponent,
                                    productType: info.product,
                                    lastBackup: info.date,
                                    size: size, path: dir.path))
        }
        return out.sorted { ($0.lastBackup ?? .distantPast) < ($1.lastBackup ?? .distantPast) }
    }

    /// Parse the fields we show from a backup's `Info.plist` (device name, model, last-backup date).
    static func readInfo(_ url: URL, fm: FileManager = .default) -> (name: String?, product: String?, date: Date?) {
        guard let data = try? Data(contentsOf: url),
              let plist = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            return (nil, nil, nil)
        }
        return (plist["Device Name"] as? String, plist["Product Type"] as? String, plist["Last Backup Date"] as? Date)
    }
}
