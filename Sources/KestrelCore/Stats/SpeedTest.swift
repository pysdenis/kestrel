import Foundation

public struct SpeedTestResult: Sendable, Equatable {
    public let downloadMbps: Double
    public let latencyMs: Double

    public init(downloadMbps: Double, latencyMs: Double) {
        self.downloadMbps = downloadMbps
        self.latencyMs = latencyMs
    }
}

/// On-demand internet speed test. Streams a payload from Cloudflare's public speed
/// endpoint and reports the running download rate as bytes arrive (so the UI can climb
/// live), then returns the final figure plus latency. User-initiated network I/O that
/// uploads nothing — no telemetry.
public struct SpeedTest {
    public enum SpeedTestError: Error { case badResponse }

    private let host: String

    public init(host: String = "https://speed.cloudflare.com") {
        self.host = host
    }

    public func run(bytes: Int = 30_000_000, onProgress: @escaping (Double) -> Void = { _ in }) async throws -> SpeedTestResult {
        let latency = try await measureLatency()
        let mbps = try await liveDownload(bytes: bytes, onProgress: onProgress)
        return SpeedTestResult(downloadMbps: mbps, latencyMs: latency)
    }

    // MARK: - Internals

    private func config() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.urlCache = nil
        return c
    }

    private func downloadURL(_ bytes: Int) throws -> URL {
        guard let url = URL(string: "\(host)/__down?bytes=\(bytes)") else { throw SpeedTestError.badResponse }
        return url
    }

    private func liveDownload(bytes: Int, onProgress: @escaping (Double) -> Void) async throws -> Double {
        let url = try downloadURL(bytes)
        return try await withCheckedThrowingContinuation { continuation in
            let probe = SpeedProbe(onProgress: onProgress) { result in continuation.resume(with: result) }
            let session = URLSession(configuration: config(), delegate: probe, delegateQueue: nil)
            probe.session = session
            session.dataTask(with: url).resume()
        }
    }

    private func measureLatency(samples: Int = 4) async throws -> Double {
        let session = URLSession(configuration: config())
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<samples {
            let start = Date()
            _ = try await session.data(from: try downloadURL(0))
            best = min(best, Date().timeIntervalSince(start) * 1000)
        }
        return best == .greatestFiniteMagnitude ? 0 : best
    }
}

/// Accumulates streamed bytes and reports the running Mbps, resuming the continuation
/// with the final rate on completion.
private final class SpeedProbe: NSObject, URLSessionDataDelegate {
    var session: URLSession?
    private var received = 0
    private var start: Date?
    private var finished = false
    private let onProgress: (Double) -> Void
    private let completion: (Result<Double, Error>) -> Void

    init(onProgress: @escaping (Double) -> Void, completion: @escaping (Result<Double, Error>) -> Void) {
        self.onProgress = onProgress
        self.completion = completion
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if start == nil { start = Date() }            // time from the first byte
        received += data.count
        guard let start else { return }
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > 0.08 { onProgress(Double(received) * 8 / elapsed / 1_000_000) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }
        finished = true
        defer { self.session?.finishTasksAndInvalidate(); self.session = nil }
        if let error {
            completion(.failure(error))
            return
        }
        let elapsed = start.map { Date().timeIntervalSince($0) } ?? 0
        completion(.success(elapsed > 0 ? Double(received) * 8 / elapsed / 1_000_000 : 0))
    }
}
