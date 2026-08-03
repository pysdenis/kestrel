import SwiftUI
import AppKit
import KestrelCore

/// A ⌘K command palette — search and run any action or jump to any section. Kestrel's
/// own take (not a menu clone): tinted icon chips, a highlighted first match that Enter
/// runs, and a keyboard hint footer.
struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var selected = 0
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    private struct Command: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        var tint: Color = Palette.accent
        let run: () -> Void
    }

    private var commands: [Command] {
        var out: [Command] = []
        for section in AppSection.allCases {
            out.append(Command(title: "Go to \(section.title)", subtitle: "Section", icon: section.icon) {
                model.section = section
            })
        }
        out.append(Command(title: "Run speed test", subtitle: "Network", icon: "speedometer", tint: Palette.teal) { model.runSpeedTest(); model.section = .dashboard })
        out.append(Command(title: "Free up space", subtitle: "Cleanup", icon: "sparkles", tint: Palette.accent) { model.section = .cleanup })
        out.append(Command(title: "Run Smart Care", subtitle: "Smart Care", icon: "wand.and.stars", tint: Palette.accent) {
            model.section = .smartcare
            let home = model.paths.home
            model.smartcare.run(home: home, downloads: home.appendingPathComponent("Downloads"))
        })
        out.append(Command(title: "Ask the assistant", subtitle: "AI", icon: "bubble.left.and.sparkles", tint: Palette.violet) { model.section = .assistant })
        out.append(Command(title: "Reveal ~/.kestrel in Finder", subtitle: "Vault & logs", icon: "folder", tint: Palette.accent2) {
            NSWorkspace.shared.activateFileViewerSelecting([model.paths.root])
        })
        return out
    }

    private var filtered: [Command] {
        query.isEmpty ? commands : commands.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.accent)
                TextField("Search or run a command…", text: $query)
                    .textFieldStyle(.plain).font(.title3)
                    .focused($focused)
                    .onSubmit { runSelected() }
                    .onChange(of: query) { _ in selected = 0 }
                Text("esc").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(16)
            Hairline()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { i, command in
                            row(command, highlighted: i == selected).id(i)
                        }
                        if filtered.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "questionmark.circle").font(.title).foregroundStyle(.tertiary)
                                Text("No matching commands.").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(28)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)
                .onChange(of: selected) { new in withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(new, anchor: .center) } }
            }
            Hairline()
            HStack(spacing: 14) {
                hint("return", "run")
                hint("esc", "dismiss")
                Spacer()
                Text("\(filtered.count) command(s)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .frame(width: 520)
        .background(.regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
        .onAppear { focused = true; installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        .overlay(alignment: .topTrailing) {
            Button("", action: dismiss).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
        }
    }

    /// Arrow-key navigation via a local key monitor — ↑/↓ move the selection, Return runs
    /// it. Reads/writes @State through its stable storage, so it always sees the current
    /// query and selection.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let count = filtered.count
            switch event.keyCode {
            case 125: // down
                if count > 0 { selected = min(selected + 1, count - 1) }
                return nil
            case 126: // up
                if count > 0 { selected = max(selected - 1, 0) }
                return nil
            case 36, 76: // return / enter
                runSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func row(_ command: Command, highlighted: Bool) -> some View {
        Button { run(command) } label: {
            HStack(spacing: 12) {
                Image(systemName: command.icon).font(.system(size: 13, weight: .medium)).foregroundStyle(command.tint)
                    .frame(width: 30, height: 30)
                    .background(command.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(command.title).font(.callout.weight(.medium))
                Spacer()
                Text(command.subtitle).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(highlighted ? Palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.caption2.monospaced()).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func run(_ command: Command) { command.run(); dismiss() }
    private func runSelected() {
        let list = filtered
        if list.indices.contains(selected) { run(list[selected]) }
        else if let first = list.first { run(first) }
    }
    private func dismiss() { removeKeyMonitor(); model.showPalette = false }
}
