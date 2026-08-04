import SwiftUI
import AppKit
import Darwin
import KestrelCore

/// Resolves a running process (pid) to the *application* it belongs to — a friendly name
/// and icon — so Energy shows "Google Chrome" with its icon instead of a raw helper name
/// like "Google Chrome Helper (Renderer)".
enum AppResolver {
    struct Info { let name: String; let url: URL? }

    static func appInfo(forPid pid: Int) -> Info {
        // 1. If the pid is an app's main process, ask the workspace directly.
        if let running = NSRunningApplication(processIdentifier: pid_t(pid)), let name = running.localizedName {
            return Info(name: name, url: running.bundleURL)
        }
        // 2. Otherwise resolve the executable path and walk up to the outermost `.app`
        //    (a Chrome renderer lives inside Google Chrome.app → "Google Chrome").
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        if count > 0 {
            let path = String(cString: buffer)
            let components = path.components(separatedBy: "/")
            if let idx = components.firstIndex(where: { $0.hasSuffix(".app") }) {
                let appPath = "/" + components[1...idx].joined(separator: "/")
                let name = FileManager.default.displayName(atPath: appPath).replacingOccurrences(of: ".app", with: "")
                return Info(name: name, url: URL(fileURLWithPath: appPath))
            }
        }
        // 3. A daemon / system process — no app; show its own name.
        return Info(name: "", url: nil)
    }
}

/// Holds per-process AI explanations for the Energy section, so they persist across the
/// list refreshing and navigation.
@MainActor final class EnergyController: ObservableObject {
    @Published var explanations: [Int: String] = [:]     // keyed by pid
    @Published var explaining: Set<Int> = []

    /// On-demand only (invariant #7): asks the opt-in assistant why a process is drawing
    /// power. Sends just the app/process name and its CPU/energy figures — never file
    /// contents.
    func explain(_ proc: ProcessEnergy, assistant: AIAssistant?) {
        guard let assistant, explanations[proc.pid] == nil, !explaining.contains(proc.pid) else { return }
        explaining.insert(proc.pid)
        let resolved = AppResolver.appInfo(forPid: proc.pid).name
        let subject = resolved.isEmpty ? proc.name : resolved
        Task { [weak self] in
            let question = "In one or two short, honest sentences, explain why “\(subject)” (process \(proc.name)) might be using about \(Int(proc.cpuPercent))% CPU and drawing power right now, and give one practical tip. Don't invent specifics."
            let text = (try? await assistant.ask(question, context: "")) ?? "Couldn't reach the assistant — check your key and connection."
            await MainActor.run { [weak self] in self?.explanations[proc.pid] = text; self?.explaining.remove(proc.pid) }
        }
    }
}
