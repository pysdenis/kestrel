import SwiftUI
import AppKit
import KestrelCore

/// A ⌘K command palette — search and run any action or jump to any section. Kestrel's
/// own take (not a menu clone), for fast keyboard-driven navigation.
struct CommandPaletteView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @FocusState private var focused: Bool

    private struct Command: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let icon: String
        let run: () -> Void
    }

    private var commands: [Command] {
        var out: [Command] = []
        for section in AppSection.allCases {
            out.append(Command(title: "Go to \(section.title)", subtitle: "Section", icon: section.icon) {
                model.section = section
            })
        }
        out.append(Command(title: "Run speed test", subtitle: "Network", icon: "speedometer") { model.runSpeedTest(); model.section = .dashboard })
        out.append(Command(title: "Free up space", subtitle: "Cleanup", icon: "sparkles") { model.section = .cleanup })
        out.append(Command(title: "Ask the assistant", subtitle: "AI", icon: "bubble.left.and.sparkles") { model.section = .assistant })
        out.append(Command(title: "Reveal ~/.kestrel in Finder", subtitle: "Vault & logs", icon: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([model.paths.root])
        })
        return out
    }

    private var filtered: [Command] {
        query.isEmpty ? commands : commands.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search or run a command…", text: $query)
                    .textFieldStyle(.plain).font(.title3)
                    .focused($focused)
                    .onSubmit { runFirst() }
                Text("esc").font(.caption.monospaced()).foregroundStyle(.tertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(14)
            Hairline()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filtered) { command in
                        Button { run(command) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: command.icon).foregroundStyle(Palette.accent).frame(width: 22)
                                Text(command.title)
                                Spacer()
                                Text(command.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text("No matching commands.").foregroundStyle(.secondary).padding(20)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 480)
        .background(.regularMaterial)
        .onAppear { focused = true }
        .overlay(alignment: .topTrailing) {
            Button("", action: dismiss).keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
        }
    }

    private func run(_ command: Command) { command.run(); dismiss() }
    private func runFirst() { if let first = filtered.first { run(first) } }
    private func dismiss() { model.showPalette = false }
}
