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
    @Published var updates: [OutdatedCask] = []
    @Published var loading = false
    @Published var busy = false
    @Published var message: String?
    @Published var query = ""

    private let paths: KestrelPaths
    private var loadedUpdates = false
    private var loaded = false
    init(paths: KestrelPaths) { self.paths = paths }

    var filtered: [AppInfo] {
        query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.bundleId?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    /// Scan installed apps. Guarded so navigating in and out doesn't re-measure every
    /// bundle each time; pass `force` after an uninstall to refresh.
    func load(force: Bool = false) {
        guard force || (!loaded && !loading) else { return }
        loaded = true
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

    private func applySizes(_ sizes: [String: Int64]) {
        apps = apps.map { var a = $0; a.size = sizes[$0.url.path]; return a }
    }

    /// A prepared, itemized plan awaiting the user's confirmation — so they see exactly
    /// which bundle and leftover files will move to the vault before anything happens.
    struct Pending: Identifiable {
        let id = UUID()
        let app: AppInfo
        let plan: CleanupPlan
        let reset: Bool
    }
    @Published var pending: Pending?
    @Published var preparing = false

    func prepareUninstall(_ app: AppInfo) { prepare(app, reset: false) }
    func prepareReset(_ app: AppInfo) { prepare(app, reset: true) }
    func cancelPending() { pending = nil }

    private func prepare(_ app: AppInfo, reset: Bool) {
        guard !preparing, !busy else { return }
        preparing = true; message = nil
        let url = app.url
        Task.detached { [weak self] in
            let plan = (try? (reset ? AppUninstaller().resetPlan(for: url) : AppUninstaller().plan(for: url))) ?? CleanupPlan(items: [])
            await MainActor.run { self?.pending = Pending(app: app, plan: plan, reset: reset); self?.preparing = false }
        }
    }

    /// Execute the reviewed plan: move everything it lists to the vault (undoable, audited).
    func confirmPending() {
        guard let pending, !busy else { return }
        self.pending = nil
        busy = true
        let plan = pending.plan, name = pending.app.name, reset = pending.reset
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let result: ExecutionResult? = plan.items.isEmpty ? nil
                : try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run {
                let verb = reset ? "Reset" : "Uninstalled"
                self?.message = plan.items.isEmpty ? "\(name) had nothing to \(reset ? "reset" : "remove")."
                    : (result.map { r in
                        var m = "\(verb) \(name) — moved \(r.movedCount) item(s), \(bytesString(r.movedBytes)) to the vault (undoable)."
                        if !r.failures.isEmpty { m += " \(r.failures.count) couldn't be moved (permissions?)." }
                        return m
                    } ?? "Couldn't \(reset ? "reset" : "uninstall") \(name).")
                self?.busy = false
                if !reset { self?.load(force: true) }
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
                        AppCard(app: app, busy: controller.busy || controller.preparing,
                                onUninstall: { controller.prepareUninstall(app) }, onReset: { controller.prepareReset(app) })
                    }
                }
            }
        }
        .overlay {
            if let pending = controller.pending {
                PlanReviewModal(
                    icon: pending.reset ? "arrow.counterclockwise" : "trash",
                    tint: pending.reset ? Palette.warn : Palette.crit,
                    title: "\(pending.reset ? "Reset" : "Uninstall") \(pending.app.name)?",
                    subtitle: pending.plan.items.isEmpty
                        ? "Nothing was found to \(pending.reset ? "reset" : "remove")."
                        : "These \(pending.plan.count) item(s) — \(bytesString(pending.plan.totalBytes)) — will move to the vault. Undoable.",
                    plan: pending.plan,
                    confirmLabel: pending.plan.items.isEmpty ? "Close" : (pending.reset ? "Reset" : "Uninstall"),
                    onConfirm: { controller.confirmPending() },
                    onCancel: { controller.cancelPending() }
                )
                .zIndex(10)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: controller.pending?.id)
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

}

/// A modal that lists exactly which files a destructive action will move to the vault —
/// full paths, sizes and reasons — so the user sees precisely what will be removed before
/// confirming. Reused by the uninstaller (and available to other plan-based actions).
struct PlanReviewModal: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let plan: CleanupPlan
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().contentShape(Rectangle()).onTapGesture(perform: onCancel)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(tint)
                        .frame(width: 44, height: 44).background(tint.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(16)
                Hairline()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(plan.items.sorted { $0.entry.size > $1.entry.size }.enumerated()), id: \.offset) { i, item in
                            if i > 0 { Hairline() }
                            HStack(spacing: 12) {
                                Text(bytesString(item.entry.size)).font(.caption.monospacedDigit().weight(.medium))
                                    .frame(width: 70, alignment: .leading).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.entry.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                                    Text(item.entry.url.path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                                    Text(item.reason).font(.caption2).foregroundStyle(.secondary.opacity(0.7)).lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        if plan.items.isEmpty {
                            EmptyState(icon: "checkmark.circle", title: "Nothing to remove", tint: Palette.good).padding(.vertical, 10)
                        }
                    }
                }
                .frame(maxHeight: 320)
                Hairline()
                HStack {
                    if !plan.items.isEmpty {
                        Text("\(plan.count) item(s) · \(bytesString(plan.totalBytes))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel", action: onCancel).buttonStyle(.kestrel(.subtle))
                    Button(confirmLabel, action: onConfirm).buttonStyle(.kestrel(.prominent, tint: tint))
                }
                .padding(14)
            }
            .frame(width: 560)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 34, y: 14)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}

/// One application, as a card: icon, name, identifier, size and Uninstall / Reset actions.
/// The icon is loaded per-card on appear, so only visible cells (LazyVGrid) touch
/// NSWorkspace — no upfront main-thread stampede across every installed app.
struct AppCard: View {
    let app: AppInfo
    let busy: Bool
    let onUninstall: () -> Void
    let onReset: () -> Void
    @State private var icon: NSImage?

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary) }
                    }
                    .frame(width: 40, height: 40)
                    .onAppear { if icon == nil { icon = NSWorkspace.shared.icon(forFile: app.url.path) } }
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
