import Foundation

/// One user-installed system add-on (Quick Look plugin, preference pane, screen saver, browser
/// plug-in, Audio Unit, Spotlight importer, color picker). The kind of thing that accumulates and
/// nobody prunes. Read-only listing; anything under `/System` is never included.
public struct SystemAddon: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case quickLook, prefPane, screenSaver, internetPlugin, audioPlugin, spotlightImporter, colorPicker
        public var label: String {
            switch self {
            case .quickLook: return "Quick Look"
            case .prefPane: return "Preference Pane"
            case .screenSaver: return "Screen Saver"
            case .internetPlugin: return "Internet Plug-In"
            case .audioPlugin: return "Audio Unit"
            case .spotlightImporter: return "Spotlight Importer"
            case .colorPicker: return "Color Picker"
            }
        }
    }

    public let kind: Kind
    public let name: String
    public let path: String
    public let size: Int64
    public let systemWide: Bool   // /Library (all users) vs ~/Library (this user)

    public var id: String { path }

    public init(kind: Kind, name: String, path: String, size: Int64, systemWide: Bool) {
        self.kind = kind; self.name = name; self.path = path; self.size = size; self.systemWide = systemWide
    }
}

/// Inventories user-facing add-ons across `~/Library` and `/Library` (never `/System`). Read-only.
public struct ExtensionInventory {
    /// (kind, Library-relative subdir, bundle extension).
    static let locations: [(kind: SystemAddon.Kind, subdir: String, ext: String)] = [
        (.quickLook, "QuickLook", "qlgenerator"),
        (.prefPane, "PreferencePanes", "prefPane"),
        (.screenSaver, "Screen Savers", "saver"),
        (.internetPlugin, "Internet Plug-Ins", "plugin"),
        (.audioPlugin, "Audio/Plug-Ins/Components", "component"),
        (.spotlightImporter, "Spotlight", "mdimporter"),
        (.colorPicker, "ColorPickers", "colorPicker"),
    ]

    private let fm: FileManager
    public init(fm: FileManager = .default) { self.fm = fm }

    public func list(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [SystemAddon] {
        var out: [SystemAddon] = []
        let roots: [(URL, Bool)] = [(home.appendingPathComponent("Library"), false),
                                    (URL(fileURLWithPath: "/Library"), true)]
        for (libraryRoot, systemWide) in roots {
            for loc in Self.locations {
                let dir = libraryRoot.appendingPathComponent(loc.subdir)
                guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for bundle in entries where bundle.pathExtension == loc.ext {
                    let size = directorySize(bundle)
                    out.append(SystemAddon(kind: loc.kind,
                                           name: bundle.deletingPathExtension().lastPathComponent,
                                           path: bundle.path, size: size, systemWide: systemWide))
                }
            }
        }
        return out.sorted { $0.size > $1.size }
    }

    func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        var total: Int64 = 0
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else { return 0 }
        for case let file as URL in en {
            let v = try? file.resourceValues(forKeys: Set(keys))
            guard v?.isRegularFile == true, v?.isSymbolicLink != true else { continue }
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? v?.fileSize ?? 0)
        }
        return total
    }
}
