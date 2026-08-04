import SwiftUI
import AppKit
import CoreServices
import KestrelCore

/// A discovered application: its bundle, name, identifier and (lazily measured) size and
/// last-used date.
struct AppInfo: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleId: String?
    var size: Int64?
    var lastUsed: Date?

    /// Days since the app was last opened (via Spotlight), or nil if unknown.
    var daysUnused: Int? { lastUsed.map { Int(Date().timeIntervalSince($0) / 86400) } }

    /// The app's last-used date from Spotlight metadata (kMDItemLastUsedDate).
    static func lastUsed(_ url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}

/// How the app list is ordered.
enum AppSort: String, CaseIterable, Identifiable {
    case name, size, lastUsed
    var id: String { rawValue }
    var label: String {
        switch self { case .name: return "Name"; case .size: return "Size"; case .lastUsed: return "Oldest first" }
    }
}

@MainActor final class AppsController: ObservableObject {
    @Published var apps: [AppInfo] = []
    @Published var updates: [OutdatedCask] = []
    @Published var loading = false
    @Published var busy = false
    @Published var message: String?
    @Published var query = ""
    @Published var sort: AppSort = .name

    private let paths: KestrelPaths
    private var loadedUpdates = false
    private var loaded = false
    init(paths: KestrelPaths) { self.paths = paths }

    /// Apps not opened in over 90 days (only counts ones with a known last-used date).
    static let unusedThresholdDays = 90
    var unused: [AppInfo] { apps.filter { ($0.daysUnused ?? 0) > Self.unusedThresholdDays } }
    var totalSize: Int64 { apps.compactMap(\.size).reduce(0, +) }

    var filtered: [AppInfo] {
        let matched = query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.bundleId?.localizedCaseInsensitiveContains(query) ?? false) }
        switch sort {
        case .name: return matched.sorted { $0.name.lowercased() < $1.name.lowercased() }
        case .size: return matched.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        // Oldest / least-recently-used first (uninstall candidates on top); apps with an
        // unknown last-used date sink to the bottom rather than masquerade as "oldest".
        case .lastUsed: return matched.sorted { ($0.lastUsed ?? .distantFuture) < ($1.lastUsed ?? .distantFuture) }
        }
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
                                         bundleId: AppUninstaller().bundleIdentifier(of: url), size: nil,
                                         lastUsed: AppInfo.lastUsed(url)))
                }
            }
            found.sort { $0.name.lowercased() < $1.name.lowercased() }
            let sorted = found
            await MainActor.run { [weak self] in
                self?.apps = sorted
                self?.loading = false
            }
            // Measure sizes in the background, then merge them in one update.
            var sizeMap: [String: Int64] = [:]
            for info in sorted { sizeMap[info.url.path] = Self.bundleSize(info.url) }
            let sizes = sizeMap
            await MainActor.run { [weak self] in self?.applySizes(sizes) }
        }

        guard !loadedUpdates else { return }
        loadedUpdates = true
        Task.detached { [weak self] in
            let casks = AppUpdater().outdatedCasks()
            await MainActor.run { [weak self] in self?.updates = casks }
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
        var batchCount: Int = 1
        var title: String { batchCount > 1 ? "\(L("Uninstall")) \(batchCount) \(L("apps"))?" : "\(reset ? L("Reset") : L("Uninstall")) \(app.name)?" }
    }
    @Published var pending: Pending?
    @Published var preparing = false

    /// Multi-select for batch uninstall (app id = bundle path).
    @Published var selected: Set<String> = []
    func toggleSelect(_ app: AppInfo) {
        if selected.contains(app.id) { selected.remove(app.id) } else { selected.insert(app.id) }
    }
    func clearSelection() { selected.removeAll() }

    func prepareUninstall(_ app: AppInfo) { prepare(app, reset: false) }
    func prepareReset(_ app: AppInfo) { prepare(app, reset: true) }
    func cancelPending() { pending = nil }

    private func prepare(_ app: AppInfo, reset: Bool) {
        guard !preparing, !busy else { return }
        preparing = true; message = nil
        let url = app.url
        Task.detached { [weak self] in
            let plan = (try? (reset ? AppUninstaller().resetPlan(for: url) : AppUninstaller().plan(for: url))) ?? CleanupPlan(items: [])
            await MainActor.run { [weak self] in self?.pending = Pending(app: app, plan: plan, reset: reset); self?.preparing = false }
        }
    }

    /// Build one combined review plan for every selected app.
    func prepareUninstallSelected() {
        guard !preparing, !busy else { return }
        let apps = self.apps.filter { selected.contains($0.id) }
        guard let first = apps.first else { return }
        preparing = true; message = nil
        Task.detached { [weak self] in
            var items: [CleanupItem] = []
            for app in apps {
                if let plan = try? AppUninstaller().plan(for: app.url) { items.append(contentsOf: plan.items) }
            }
            let plan = CleanupPlan(items: items)
            await MainActor.run { [weak self] in
                self?.pending = Pending(app: first, plan: plan, reset: false, batchCount: apps.count)
                self?.preparing = false
            }
        }
    }

    /// Execute the reviewed plan: move everything it lists to the vault (undoable, audited).
    func confirmPending() {
        guard let pending, !busy else { return }
        self.pending = nil
        busy = true
        let plan = pending.plan, name = pending.app.name, reset = pending.reset
        let batch = pending.batchCount
        let vaultURL = paths.vault, auditURL = paths.auditLog
        Task.detached { [weak self] in
            let result: ExecutionResult? = plan.items.isEmpty ? nil
                : try? CleanupExecutor(vault: VaultService(vaultRoot: vaultURL), audit: AuditLog(url: auditURL)).execute(plan, apply: true)
            await MainActor.run { [weak self] in
                let subject = batch > 1 ? "\(batch) apps" : name
                let verb = reset ? "Reset" : "Uninstalled"
                self?.message = plan.items.isEmpty ? "\(subject) had nothing to \(reset ? "reset" : "remove")."
                    : (result.map { "\(verb) \(subject) — moved \($0.movedCount) item(s), \(bytesString($0.movedBytes)) to the vault (undoable).\($0.failureSuffix)" }
                        ?? "Couldn't \(reset ? "reset" : "uninstall") \(subject).")
                self?.busy = false
                self?.clearSelection()
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
            if !controller.unused.isEmpty { unusedCard }

            searchCard
            statsRow

            if !controller.selected.isEmpty { selectionBar }

            if controller.loading {
                ScanningBanner(title: "Reading your applications…", detail: "Measuring bundle sizes", tint: Palette.accent2)
            } else if controller.filtered.isEmpty {
                Card { EmptyState(icon: "app.dashed", title: "No apps match", caption: "Try a different search.", tint: Palette.accent) }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(controller.filtered) { app in
                        AppCard(app: app, busy: controller.busy || controller.preparing,
                                selected: controller.selected.contains(app.id),
                                onToggleSelect: { controller.toggleSelect(app) },
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
                    title: pending.title,
                    subtitle: pending.plan.items.isEmpty
                        ? "\(L("Nothing was found to")) \(pending.reset ? L("reset") : L("remove"))."
                        : "\(L("These")) \(pending.plan.count) \(L("item(s) —")) \(bytesString(pending.plan.totalBytes)) \(L("— will move to the vault. Undoable."))",
                    plan: pending.plan,
                    confirmLabel: pending.plan.items.isEmpty ? L("Close") : (pending.reset ? L("Reset") : L("Uninstall")),
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
                Text(L("From Homebrew casks — advisory; Kestrel never updates silently.")).font(.caption).foregroundStyle(.secondary)
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
                TextField(L("Search applications…"), text: $controller.query)
                    .textFieldStyle(.plain)
                Spacer()
                Text("\(controller.filtered.count) \(L("app(s)"))").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            if controller.totalSize > 0 {
                Label("\(bytesString(controller.totalSize)) \(L("total"))", systemImage: "internaldrive")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(L("Sort")).font(.caption).foregroundStyle(.tertiary)
            KestrelSelect(items: AppSort.allCases, selection: $controller.sort, label: { L($0.label) })
        }
    }

    private var unusedCard: some View {
        Card(tint: Palette.warn) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark").font(.title2).foregroundStyle(Palette.warn)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(controller.unused.count) \(L("apps unused for 90+ days"))").font(.subheadline.weight(.semibold))
                    Text("\(bytesString(controller.unused.compactMap(\.size).reduce(0, +))) \(L("— review and uninstall the ones you don't need."))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { controller.query = ""; controller.sort = .lastUsed } label: { Label(L("Show oldest"), systemImage: "arrow.up.arrow.down") }
                    .buttonStyle(.kestrel(.secondary, tint: Palette.warn, size: .small))
            }
        }
    }

    private var selectionBar: some View {
        Card(padding: 10, tint: Palette.crit) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.crit)
                Text("\(controller.selected.count) \(L("selected"))").font(.callout.weight(.medium))
                Spacer()
                Button(L("Clear")) { controller.clearSelection() }.buttonStyle(.kestrel(.subtle, size: .small))
                Button { controller.prepareUninstallSelected() } label: {
                    if controller.preparing { KestrelSpinner(tint: .white, size: 14) }
                    else { Label("\(L("Uninstall")) \(controller.selected.count)", systemImage: "trash") }
                }
                .buttonStyle(.kestrel(.prominent, tint: Palette.crit, size: .small))
                .disabled(controller.preparing || controller.busy)
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
    var selected: Bool = false
    var onToggleSelect: () -> Void = {}
    let onUninstall: () -> Void
    let onReset: () -> Void
    @State private var icon: NSImage?

    var body: some View {
        Card(tint: selected ? Palette.crit : nil) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button(action: onToggleSelect) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(selected ? Palette.crit : Color.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain).help(L("Select for batch uninstall"))
                    Group {
                        if let icon { Image(nsImage: icon).resizable() }
                        else { Image(systemName: "app.fill").resizable().foregroundStyle(.tertiary) }
                    }
                    .frame(width: 40, height: 40)
                    .onAppear { if icon == nil { icon = NSWorkspace.shared.icon(forFile: app.url.path) } }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                        HStack(spacing: 5) {
                            if let days = app.daysUnused {
                                Image(systemName: "clock").font(.system(size: 8))
                                Text(days > (AppsController.unusedThresholdDays) ? "\(L("unused")) \(days)d" : "\(days)d")
                                    .foregroundStyle(days > AppsController.unusedThresholdDays ? Palette.warn : Color.secondary)
                            }
                            Text(app.bundleId ?? app.url.path).lineLimit(1).truncationMode(.middle)
                        }
                        .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let size = app.size {
                        Text(bytesString(size)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(.secondary)
                    } else {
                        KestrelSpinner(size: 12)
                    }
                }
                HStack(spacing: 8) {
                    Button(action: onUninstall) { Label(L("Uninstall"), systemImage: "trash") }
                        .buttonStyle(.kestrel(.secondary, tint: Palette.crit, size: .small)).disabled(busy)
                    Button(action: onReset) { Label(L("Reset"), systemImage: "arrow.counterclockwise") }
                        .buttonStyle(.kestrel(.subtle, size: .small)).disabled(busy)
                    Spacer()
                    Button { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.kestrel(.subtle, size: .small)).help(L("Reveal in Finder"))
                }
            }
        }
    }
}
