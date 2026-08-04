import SwiftUI
import AppKit
import KestrelCore

@MainActor final class PermissionsController: ObservableObject {
    struct AppPermissions: Identifiable {
        var id: String { client }
        let client: String
        var name: String
        var icon: NSImage?
        let items: [TCCPermission]
        var allowedCount: Int { items.filter(\.allowed).count }
    }

    @Published var groups: [AppPermissions] = []
    @Published var loading = false
    @Published var query = ""
    private var loaded = false

    var filteredGroups: [AppPermissions] {
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.client.localizedCaseInsensitiveContains(query) }
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        loading = true
        Task.detached { [weak self] in
            let perms = TCCReader().permissions()
            let grouped = Dictionary(grouping: perms, by: { $0.client })
                .map { (client: $0.key, items: $0.value.sorted { $0.service < $1.service }) }
            await MainActor.run { [weak self] in self?.resolve(grouped) }
        }
    }

    private func resolve(_ grouped: [(client: String, items: [TCCPermission])]) {
        groups = grouped.map { entry in
            let (name, icon) = Self.appInfo(for: entry.client)
            return AppPermissions(client: entry.client, name: name, icon: icon, items: entry.items)
        }
        .sorted { $0.allowedCount != $1.allowedCount ? $0.allowedCount > $1.allowedCount : $0.name.lowercased() < $1.name.lowercased() }
        loading = false
    }

    /// Resolve a TCC client (bundle id or path) to a display name and icon.
    private static func appInfo(for client: String) -> (String, NSImage?) {
        if client.contains("/") {
            let url = URL(fileURLWithPath: client)
            return (url.deletingPathExtension().lastPathComponent, NSWorkspace.shared.icon(forFile: client))
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return (name, NSWorkspace.shared.icon(forFile: url.path))
        }
        return (client.components(separatedBy: ".").last ?? client, nil)
    }
}

struct PermissionsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: PermissionsController

    var body: some View {
        SectionScaffold(title: "Permissions", subtitle: "Which apps hold Camera, Microphone, Full Disk Access and more — read-only") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            Card {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(Palette.accent)
                    Text(L("Per-user privacy grants, read-only from your TCC database. System-level ones like Full Disk Access and Accessibility live in a root-only database and may not all appear here — manage everything in System Settings."))
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: { Label(L("Open Privacy settings"), systemImage: "arrow.up.forward.app") }
                        .buttonStyle(.kestrel(.secondary, size: .small))
                }
            }

            if controller.loading {
                ScanningBanner(title: "Reading privacy grants…", detail: "From the TCC database", tint: Palette.accent)
            } else if controller.groups.isEmpty {
                Card {
                    EmptyState(icon: model.fullDiskAccess ? "checkmark.shield" : "lock.shield",
                               title: model.fullDiskAccess ? "No app permissions found" : "Full Disk Access needed",
                               caption: model.fullDiskAccess ? "Nothing has requested a protected resource yet."
                                                             : "Grant Kestrel Full Disk Access to read the privacy database.",
                               tint: Palette.accent)
                }
            } else {
                Card(padding: 10) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(L("Search apps…"), text: $controller.query).textFieldStyle(.plain)
                        Spacer()
                        Text("\(controller.filteredGroups.count) \(L("app(s)"))").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(controller.filteredGroups) { PermissionCard(app: $0) }
                }
            }
        }
        .onAppear { controller.load() }
    }
}

/// One app and the protected resources it holds, as pills (green = allowed).
struct PermissionCard: View {
    let app: PermissionsController.AppPermissions

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let icon = app.icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary) }
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Text(app.client).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(app.items.enumerated()), id: \.offset) { _, perm in
                        PermissionPill(name: TCCReader.friendlyService(perm.service), allowed: perm.allowed)
                    }
                }
            }
        }
    }
}

/// A permission pill: an icon + label, green when allowed, muted with a slash when denied.
struct PermissionPill: View {
    let name: String
    let allowed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(for: name)).imageScale(.small)
            Text(L(name)).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(allowed ? AnyShapeStyle(Palette.good) : AnyShapeStyle(Color.secondary))
        .background((allowed ? Palette.good : Color.secondary).opacity(0.14), in: Capsule())
        .overlay(allowed ? nil : Capsule().strokeBorder(.secondary.opacity(0.2)))
        .opacity(allowed ? 1 : 0.7)
    }

    static func icon(for friendly: String) -> String {
        switch friendly {
        case "Camera": return "camera.fill"
        case "Microphone": return "mic.fill"
        case "Full Disk Access": return "externaldrive.fill"
        case "Screen recording": return "rectangle.dashed.badge.record"
        case "Accessibility": return "accessibility"
        case "Automation": return "gearshape.2.fill"
        case "Input monitoring": return "keyboard.fill"
        case "Photos": return "photo.fill"
        case "Contacts": return "person.crop.circle.fill"
        case "Calendar": return "calendar"
        case "Reminders": return "checklist"
        case "Location": return "location.fill"
        case "Media library": return "music.note"
        case "Speech recognition": return "waveform"
        case "Desktop folder", "Documents folder", "Downloads folder": return "folder.fill"
        case "Network volumes", "Removable volumes": return "externaldrive.connected.to.line.below"
        default: return "lock.fill"
        }
    }
}
