import Foundation
import CoreServices

/// Watches folders (typically Downloads/Desktop) with FSEvents and scans files the
/// moment they appear or change. On a real finding it calls `onFindings`; a clean file
/// produces nothing — consistent with the "never scare" rule. This is the on-access
/// counterpart to `AntivirusEngine.scan`.
///
/// Not covered by the unit runner (it depends on live filesystem events + a run loop);
/// it is exercised end-to-end via `kestrel av watch`.
public final class OnAccessWatcher {
    private let paths: [String]
    private let engine: AntivirusEngine
    private let onFindings: ([ScanFinding]) -> Void
    private let queue = DispatchQueue(label: "com.pysdenis.kestrel.onaccess")
    private var stream: FSEventStreamRef?

    public init(paths: [URL], engine: AntivirusEngine = AntivirusEngine(), onFindings: @escaping ([ScanFinding]) -> Void) {
        self.paths = paths.map(\.path)
        self.engine = engine
        self.onFindings = onFindings
    }

    public func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<OnAccessWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.handle(Array(paths.prefix(count)))
        }
        // UseCFTypes makes eventPaths a CFArray of CFString (so the NSArray cast below is
        // valid); FileEvents gives per-file granularity; NoDefer fires promptly.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handle(_ changedPaths: [String]) {
        let fm = FileManager.default
        for path in changedPaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let findings = engine.scanFile(URL(fileURLWithPath: path))
            if !findings.isEmpty { onFindings(findings) }
        }
    }
}
