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

    enum ViewMode: String, CaseIterable, Identifiable { case byApp, byPermission; var id: String { rawValue }
        var label: String { self == .byApp ? "By app" : "By permission" }
        var icon: String { self == .byApp ? "square.grid.2x2" : "hand.raised" }
    }

    /// One protected resource and every app that currently holds it — the reverse "exposure"
    /// map (e.g. "who can see my Camera?").
    struct PermissionUsage: Identifiable {
        let service: String
        let friendly: String
        let sensitive: Bool
        let apps: [AppRef]
        var id: String { service }
        struct AppRef: Identifiable { let id: String; let name: String; let icon: NSImage?; let client: String }
    }

    @Published var groups: [AppPermissions] = []
    @Published var loading = false
    @Published var query = ""
    @Published var mode: ViewMode = .byApp
    /// Trust profile: the code-signing verdict per app, joined to its permissions by client.
    @Published var signaturesByClient: [String: CodeSignature] = [:]
    private var loaded = false

    var filteredGroups: [AppPermissions] {
        guard !query.isEmpty else { return groups }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.client.localizedCaseInsensitiveContains(query) }
    }

    /// Allowed grants regrouped by permission — sensitive ones first, then by how many apps hold them.
    var byPermission: [PermissionUsage] {
        var buckets: [String: [PermissionUsage.AppRef]] = [:]
        for app in groups {
            for perm in app.items where perm.allowed {
                buckets[perm.service, default: []].append(.init(id: app.client + "|" + perm.service, name: app.name, icon: app.icon, client: app.client))
            }
        }
        let usages = buckets.map { service, apps in
            PermissionUsage(service: service, friendly: TCCReader.friendlyService(service),
                            sensitive: TCCReader.isSensitive(service),
                            apps: apps.sorted { $0.name.lowercased() < $1.name.lowercased() })
        }
        .sorted { ($0.sensitive ? 1 : 0, $0.apps.count) > ($1.sensitive ? 1 : 0, $1.apps.count) }
        guard !query.isEmpty else { return usages }
        return usages.filter { $0.friendly.localizedCaseInsensitiveContains(query) || $0.apps.contains { $0.name.localizedCaseInsensitiveContains(query) } }
    }

    /// Deep-link to the exact Privacy pane so the user can revoke a grant in one hop.
    static func settingsURL(for rawService: String) -> URL? {
        let t = rawService.hasPrefix("kTCCService") ? String(rawService.dropFirst("kTCCService".count)) : rawService
        let anchor: String
        switch t {
        case "Camera": anchor = "Privacy_Camera"
        case "Microphone": anchor = "Privacy_Microphone"
        case "ScreenCapture": anchor = "Privacy_ScreenCapture"
        case "Accessibility": anchor = "Privacy_Accessibility"
        case "SystemPolicyAllFiles": anchor = "Privacy_AllFiles"
        case "PostEvent", "ListenEvent": anchor = "Privacy_ListenEvent"
        case "AppleEvents": anchor = "Privacy_Automation"
        case "Photos", "PhotosAdd": anchor = "Privacy_Photos"
        case "AddressBook": anchor = "Privacy_Contacts"
        case "Calendar": anchor = "Privacy_Calendars"
        case "Reminders": anchor = "Privacy_Reminders"
        case "Location", "CoreLocation", "Liverpool": anchor = "Privacy_LocationServices"
        case "MediaLibrary": anchor = "Privacy_Media"
        case "SpeechRecognition": anchor = "Privacy_SpeechRecognition"
        default: anchor = "Privacy"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
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
        loadSignatures(for: groups.map(\.client))
    }

    /// Read each app's code signature off-main and join it to its permissions — the honest
    /// "trust profile": what an app can access + who signed it, side by side (no composite score).
    private func loadSignatures(for clients: [String]) {
        let pairs = clients.map { ($0, Self.appURL(for: $0)) }
        Task.detached {
            let reader = CodeSignatureReader()
            var map: [String: CodeSignature] = [:]
            for (client, url) in pairs { if let url { map[client] = reader.read(url) } }
            let result = map   // capture an immutable copy across the actor hop (Swift 6-safe)
            await MainActor.run { self.signaturesByClient = result }
        }
    }

    /// Resolve a TCC client (bundle id or path) to the app bundle URL, if it can be found.
    static func appURL(for client: String) -> URL? {
        if client.contains("/") { return URL(fileURLWithPath: client) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: client)
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
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField(controller.mode == .byApp ? L("Search apps…") : L("Search permissions…"), text: $controller.query).textFieldStyle(.plain)
                        Spacer()
                        ForEach(PermissionsController.ViewMode.allCases) { m in
                            Button { controller.mode = m } label: {
                                Label(L(m.label), systemImage: m.icon).font(.caption.weight(.medium))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .foregroundStyle(controller.mode == m ? Color.white : Color.secondary)
                                    .background(controller.mode == m ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.quaternary), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if controller.mode == .byApp {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                        ForEach(controller.filteredGroups) { PermissionCard(app: $0, signature: controller.signaturesByClient[$0.client]) }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                        ForEach(controller.byPermission) { PermissionUsageCard(usage: $0) }
                    }
                }
            }
        }
        .onAppear { controller.load() }
    }
}

/// Reverse exposure map: one protected resource and every app that can use it, each with a
/// one-hop deep-link to revoke it in System Settings.
struct PermissionUsageCard: View {
    let usage: PermissionsController.PermissionUsage

    var body: some View {
        Card(tint: usage.sensitive ? Palette.pink : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: PermissionPill.icon(for: usage.friendly))
                        .foregroundStyle(usage.sensitive ? Palette.pink : Palette.accent)
                    Text(L(usage.friendly)).font(.subheadline.weight(.semibold))
                    if usage.sensitive {
                        Text(L("sensitive")).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1).background(Palette.pink, in: Capsule())
                    }
                    Spacer()
                    Text("\(usage.apps.count)").font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
                    Button { if let u = PermissionsController.settingsURL(for: usage.service) { NSWorkspace.shared.open(u) } } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Manage in System Settings"))
                }
                ForEach(usage.apps) { app in
                    HStack(spacing: 9) {
                        Group {
                            if let icon = app.icon { Image(nsImage: icon).resizable() }
                            else { Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary) }
                        }
                        .frame(width: 20, height: 20)
                        Text(app.name).font(.callout).lineLimit(1).truncationMode(.middle)
                        Spacer()
                    }
                }
            }
        }
    }
}

/// One app and the protected resources it holds, as pills (green = allowed) — plus its code-signing
/// verdict, so "what it can access" and "who signed it" sit side by side (the honest trust profile).
struct PermissionCard: View {
    let app: PermissionsController.AppPermissions
    var signature: CodeSignature?

    private var hasSensitive: Bool { app.items.contains { $0.allowed && TCCReader.isSensitive($0.service) } }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let icon = app.icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary) }
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        if let sig = signature {
                            let bad = sig.status.isNoteworthy
                            Label("\(L(sig.status.label))\(sig.teamID.map { " · \($0)" } ?? "")", systemImage: bad ? "exclamationmark.shield" : "checkmark.seal")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(bad ? Palette.warn : .secondary).lineLimit(1)
                        } else {
                            Text(app.client).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    if hasSensitive {
                        Label(L("sensitive"), systemImage: "eye.trianglebadge.exclamationmark")
                            .font(.system(size: 9, weight: .bold)).labelStyle(.iconOnly)
                            .foregroundStyle(Palette.pink).help(L("Holds camera, microphone, screen, input or full-disk access"))
                    }
                }
                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Array(app.items.enumerated()), id: \.offset) { _, perm in
                        PermissionPill(name: TCCReader.friendlyService(perm.service), allowed: perm.allowed,
                                       sensitive: TCCReader.isSensitive(perm.service))
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
    var sensitive: Bool = false

    private var tint: Color { !allowed ? .secondary : (sensitive ? Palette.pink : Palette.good) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Self.icon(for: name)).imageScale(.small)
            Text(L(name)).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(AnyShapeStyle(tint))
        .background(tint.opacity(0.14), in: Capsule())
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
