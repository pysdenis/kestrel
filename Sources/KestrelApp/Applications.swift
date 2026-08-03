import SwiftUI
import AppKit
import KestrelCore

/// A discovered application: its bundle, name, identifier and (lazily measured) size.
struct AppInfo: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleId: String?
    var size: Int64?
}

@MainActor final class AppsController: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var icons: [String: NSImage] = [:]
    @Published var updates: [OutdatedCask] = []
    @Published var loading = false
    @Published var busy = false
    @Published var message: String?
    @Published var query = ""

    private let paths: KestrelPaths
    private var loadedUpdates = false
    init(paths: KestrelPaths) { self.paths = paths }

    var filtered: [AppInfo] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.bundleId?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    func load() {
        guard !loading else { return }
        loading = true
        let dirs = AppUninstaller().applicationDirectories
        Task.detached { [weak self] in
            let fm = FileManager.default
            var found: [AppInfo] = []
            for dir in dirs {
                guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for url in entries where url.pathExtension == "app" {
                    found.append(AppInfo(url: url, name: url.deletingPathExtension().lastPathComponent,
                                         bundleId: AppUninstaller().bundleIdentifier(of: url), size: nil))
                }
            }
            found.sort { $0.name.lowercased() < $1.name.lowercased() }
            await MainActor.run {
                self?.apps = found
                self?.loading = false
                self?.loadIcons(found)
            }
            // Measure sizes in the background, then merge them in one update.
            var sizes: [String: Int64] = [:]
            for info in found { sizes[info.url.path] = Self.bundleSize(info.url) }
            await MainActor.run { self?.applySizes(sizes) }
        }

        guard !loadedUpdates else { return }
        loadedUpdates = true
        Task.detached { [weak self] in
            let casks = AppUpdater().outdatedCasks()
            await MainActor.run { self?.updates = casks }
        }
    }

    private func loadIcons(_ apps: [AppInfo]) {
        for app in apps where icons[app.url.path] == nil {
            icons[app.url.path] = NSWorkspace.shared.icon(forFile: app.url.path)
        }
    }

    private func applySizes(_ sizes: [String: Int64]) {
        apps = apps.map { var a = $0; a.size = sizes[$0.url.path]; return a }
    }

    /// Uninstall: move the bundle plus its leftovers to the vault (undoable). Never `rm`.
    func uninstall(_ app: AppInfo) {
        guard !busy else { return }
        busy = true; message = nil
        let url = app.url, name = app.name
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let plan = (try? AppUninstaller().plan(for: url)) ?? CleanupPlan(items: [])
            let result: ExecutionResult? = plan.items.isEmpty ? nil
                : try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run {
                self?.message = result.map { "Uninstalled \(name) — moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault (undoable)." }
                    ?? "Couldn't uninstall \(name)."
                self?.busy = false
                self?.load()
            }
        }
    }

    /// Reset: move an app's data (caches, prefs, containers…) to the vault but keep the app.
    func reset(_ app: AppInfo) {
        guard !busy else { return }
        busy = true; message = nil
        let url = app.url, name = app.name
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let plan = (try? AppUninstaller().resetPlan(for: url)) ?? CleanupPlan(items: [])
            let result: ExecutionResult? = plan.items.isEmpty ? nil
                : try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run {
                self?.message = plan.items.isEmpty ? "\(name) had no resettable data."
                    : (result.map { "Reset \(name) — moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault." } ?? "Couldn't reset \(name).")
                self?.busy = false
            }
        }
    }

    /// Allocated size of a bundle, summed over its contents.
    nonisolated static func bundleSize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in en {
            if let v = try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]), let s = v.totalFileAllocatedSize {
                total += Int64(s)
            }
        }
        return total
    }
}

struct ApplicationsSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: AppsController

    var body: some View {
        SectionScaffold(title: "Applications", subtitle: "Uninstall cleanly (bundle + leftovers → vault) and see what has updates") {
            if !model.fullDiskAccess { FullDiskAccessBanner() }

            if let message = controller.message {
                Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.good).font(.callout)
            }

            if !controller.updates.isEmpty { updatesCard }

            searchCard

            if controller.loading {
                ScanningBanner(title: "Reading your applications…", detail: "Measuring bundle sizes", tint: Palette.accent2)
            } else if controller.filtered.isEmpty {
                Card { EmptyState(icon: "app.dashed", title: "No apps match", caption: "Try a different search.", tint: Palette.accent) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(controller.filtered) { app in
                        AppCard(app: app, icon: controller.icons[app.url.path], busy: controller.busy,
                                onUninstall: { confirmUninstall(app) }, onReset: { confirmReset(app) })
                    }
                }
            }
        }
        .onAppear { controller.load() }
    }

    private var updatesCard: some View {
        Card(tint: Palette.accent2) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Updates available", icon: "arrow.up.circle")
                Text("From Homebrew casks — advisory; Kestrel never updates silently.").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(controller.updates.enumerated()), id: \.offset) { i, u in
                    if i > 0 { Hairline() }
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox").font(.caption).foregroundStyle(Palette.accent2)
                        Text(u.name).font(.callout.weight(.medium))
                        Spacer()
                        Text(u.current).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        Text(u.latest).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Palette.good)
                        CopyButton(text: "brew upgrade --cask \(u.name)")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var searchCard: some View {
        Card(padding: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search applications…", text: $controller.query)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(controller.filtered.count) app(s)").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func confirmUninstall(_ app: AppInfo) {
        model.requestConfirm(ConfirmRequest(
            icon: "trash", tint: Palette.crit,
            title: "Uninstall \(app.name)?",
            message: "Moves the app and the support files, caches and preferences it left behind to the vault. Undoable — nothing is permanently deleted until you purge.",
            confirmLabel: "Uninstall", destructive: true,
            onConfirm: { controller.uninstall(app) }
        ))
    }

    private func confirmReset(_ app: AppInfo) {
        model.requestConfirm(ConfirmRequest(
            icon: "arrow.counterclockwise", tint: Palette.warn,
            title: "Reset \(app.name)?",
            message: "Moves the app's data (caches, preferences, containers, saved state) to the vault but keeps the app itself. Undoable.",
            confirmLabel: "Reset", destructive: false,
            onConfirm: { controller.reset(app) }
        ))
    }
}

/// One application, as a card: icon, name, identifier, size and Uninstall / Reset actions.
struct AppCard: View {
    let app: AppInfo
    let icon: NSImage?
    let busy: Bool
    let onUninstall: () -> Void
    let onReset: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary) }
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        Text(app.bundleId ?? app.url.path).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let size = app.size {
                        Text(bytesString(size)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                    } else {
                        KestrelSpinner(size: 12)
                    }
                }
                HStack(spacing: 8) {
                    Button(action: onUninstall) { Label("Uninstall", systemImage: "trash") }
                        .buttonStyle(.kestrel(.secondary, tint: Palette.crit, size: .small)).disabled(busy)
                    Button(action: onReset) { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.kestrel(.subtle, size: .small)).disabled(busy)
                    Spacer()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.kestrel(.subtle, size: .small)).help("Reveal in Finder")
                }
            }
        }
    }
}
