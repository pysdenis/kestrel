import SwiftUI
import KestrelCore

/// Cleanup Time Machine — a browsable, reversible history of everything Kestrel has moved to
/// the vault. Restore a whole session or a single file, filter by age, and search by path.
/// Nothing is permanently gone until it's purged, so any past cleanup can be walked back.
@MainActor final class TimeMachineController: ObservableObject {
    enum Range: String, CaseIterable, Identifiable {
        case week, month, all
        var id: String { rawValue }
        var label: String { switch self { case .week: return "Last 7 days"; case .month: return "Last 30 days"; case .all: return "All time" } }
        var days: Double? { switch self { case .week: return 7; case .month: return 30; case .all: return nil } }
    }

    @Published var sessions: [VaultSession] = []
    @Published var loading = false
    @Published var busy = false
    @Published var message: String?
    @Published var lastOK = true
    @Published var range: Range = .all
    @Published var query = ""

    private let paths: KestrelPaths
    init(paths: KestrelPaths) { self.paths = paths }

    var totalBytes: Int64 { sessions.reduce(0) { $0 + $1.totalBytes } }
    var totalItems: Int { sessions.reduce(0) { $0 + $1.count } }

    /// Sessions within the chosen age window whose records match the search query.
    var filtered: [VaultSession] {
        let now = Date()
        return sessions.compactMap { session in
            if let days = range.days, now.timeIntervalSince(session.createdAt) > days * 86400 { return nil }
            guard !query.isEmpty else { return session }
            let matches = session.records.filter { $0.originalPath.localizedCaseInsensitiveContains(query) }
            guard !matches.isEmpty else { return nil }
            var copy = session; copy.records = matches; return copy
        }
    }

    func load() {
        loading = true
        let vaultURL = paths.vault
        Task.detached { [weak self] in
            let list = (try? VaultService(vaultRoot: vaultURL).listSessions()) ?? []
            await MainActor.run { [weak self] in self?.sessions = list; self?.loading = false }
        }
    }

    func restoreSession(_ id: String) {
        guard !busy else { return }
        busy = true; message = nil
        let vaultURL = paths.vault
        Task.detached { [weak self] in
            let outcome = try? VaultService(vaultRoot: vaultURL).undo(session: id)
            await MainActor.run { [weak self] in self?.finish(outcome); self?.load() }
        }
    }

    func restoreItem(_ originalPath: String, session id: String) {
        guard !busy else { return }
        busy = true; message = nil
        let vaultURL = paths.vault
        Task.detached { [weak self] in
            let outcome = try? VaultService(vaultRoot: vaultURL).restoreItem(originalPath: originalPath, session: id)
            await MainActor.run { [weak self] in self?.finish(outcome, single: true); self?.load() }
        }
    }

    private func finish(_ outcome: UndoOutcome?, single: Bool = false) {
        busy = false
        guard let outcome else { lastOK = false; message = L("Restore failed."); return }
        lastOK = outcome.failed.isEmpty
        var parts = ["\(L("Restored")) \(outcome.restored) \(single ? L("file") : L("item(s)"))"]
        if !outcome.skippedExisting.isEmpty { parts.append("\(outcome.skippedExisting.count) \(L("already in place"))") }
        if let f = outcome.failed.first { parts.append("\(outcome.failed.count) \(L("failed")) — \(f.reason)") }
        message = parts.joined(separator: " · ")
    }
}

struct TimeMachineSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var controller: TimeMachineController

    var body: some View {
        SectionScaffold(title: "Time Machine", subtitle: "Walk back any cleanup — restore a whole session or a single file") {
            heroCard
            if let message = controller.message {
                Label(message, systemImage: controller.lastOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(controller.lastOK ? Palette.good : Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
            if controller.loading {
                ScanningBanner(title: "Reading the vault…", detail: L("Gathering every cleanup you can undo."), tint: Palette.accent2)
            } else if controller.filtered.isEmpty {
                Card {
                    EmptyState(icon: "clock.arrow.2.circlepath",
                               title: controller.sessions.isEmpty ? "Nothing to restore yet" : "No matches",
                               caption: controller.sessions.isEmpty
                                ? "Everything a cleanup removes lands here, fully reversible until you purge it."
                                : "No cleaned items match your filter.",
                               tint: Palette.accent2)
                }
            } else {
                ForEach(controller.filtered, id: \.id) { session in
                    SessionCard(session: session, busy: controller.busy,
                                onRestoreAll: { controller.restoreSession(session.id) },
                                onRestoreItem: { controller.restoreItem($0, session: session.id) })
                }
            }
        }
        .onAppear { controller.load() }
    }

    private var heroCard: some View {
        Card(elevated: true, tint: Palette.accent2) {
            HStack(spacing: 20) {
                ZStack {
                    Circle().fill(Palette.accent2.opacity(0.14)).frame(width: 62, height: 62)
                    Image(systemName: "clock.arrow.2.circlepath").font(.system(size: 27)).foregroundStyle(Palette.accent2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(bytesString(controller.totalBytes)) \(L("restorable"))").font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("\(controller.sessions.count) \(L("cleanup(s)")) · \(controller.totalItems) \(L("items"))").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSWorkspace.shared.activateFileViewerSelecting([model.paths.vault]) } label: { Label(L("Reveal vault"), systemImage: "folder") }
                    .buttonStyle(.kestrel(.subtle, size: .small))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            KestrelSelect(items: TimeMachineController.Range.allCases, selection: $controller.range, label: { L($0.label) })
                .frame(maxWidth: 190)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                TextField(L("Search restored files…"), text: $controller.query).textFieldStyle(.plain).font(.callout)
                if !controller.query.isEmpty {
                    Button { controller.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(.quaternary.opacity(0.6), in: Capsule())
        }
    }
}

/// One cleanup in the timeline — a collapsible card with a restore-all header and per-file rows.
private struct SessionCard: View {
    let session: VaultSession
    let busy: Bool
    let onRestoreAll: () -> Void
    let onRestoreItem: (String) -> Void
    @State private var expanded = false

    private static let rel: RelativeDateTimeFormatter = { let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; return f }()

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tray.full").foregroundStyle(Palette.accent2).frame(width: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Self.rel.localizedString(for: session.createdAt, relativeTo: Date()).capitalized)
                                .font(.subheadline.weight(.semibold))
                            Text("\(session.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(session.count) \(L("item(s)"))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(bytesString(session.totalBytes)).font(.callout.weight(.semibold).monospacedDigit())
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(14)

                if expanded {
                    Hairline().padding(.horizontal, 14)
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button(action: onRestoreAll) { Label(L("Restore all"), systemImage: "arrow.uturn.backward") }
                                .buttonStyle(.kestrel(.secondary, size: .small)).disabled(busy)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        ForEach(Array(session.records.prefix(100).enumerated()), id: \.offset) { _, r in
                            HStack(spacing: 12) {
                                Text(bytesString(r.size)).font(.caption.monospacedDigit().weight(.medium))
                                    .frame(width: 64, alignment: .leading).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text((r.originalPath as NSString).lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                                    Text((r.originalPath as NSString).deletingLastPathComponent).font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Button { onRestoreItem(r.originalPath) } label: { Image(systemName: "arrow.uturn.backward.circle") }
                                    .buttonStyle(.kestrel(.subtle, size: .small)).disabled(busy).help(L("Restore this file"))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 5)
                        }
                        if session.records.count > 100 {
                            Text("+\(session.records.count - 100) \(L("more"))").font(.caption2).foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 5)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
