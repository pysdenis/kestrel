import Foundation

public struct SpeedTestResult: Sendable, Equatable {
    public let downloadMbps: Double
    public let latencyMs: Double

    public init(downloadMbps: Double, latencyMs: Double) {
        self.downloadMbps = downloadMbps
        self.latencyMs = latencyMs
    }
}

/// On-demand internet speed test. Uses Cloudflare's public speed endpoint (the same one
/// their own speed test uses) to download a payload and time it, plus a few tiny requests
/// for latency. User-initiated network I/O only — it uploads nothing, so it does not
/// violate the zero-telemetry rule; it just measures the pipe when the user asks.
public struct SpeedTest {
    public enum SpeedTestError: Error { case badResponse }

    private let host: String

    public init(host: String = "https://speed.cloudflare.com") {
        self.host = host
    }

    public func run(bytes: Int = 25_000_000) async throws -> SpeedTestResult {
        let latency = try await measureLatency()
        let mbps = try await measureDownload(bytes: bytes)
        return SpeedTestResult(downloadMbps: mbps, latencyMs: latency)
    }

    // MARK: - Internals

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    private func downloadURL(_ bytes: Int) throws -> URL {
        guard let url = URL(string: "\(host)/__down?bytes=\(bytes)") else { throw SpeedTestError.badResponse }
        return url
    }

    private func measureDownload(bytes: Int) async throws -> Double {
        let session = makeSession()
        let start = Date()
        let (data, response) = try await session.data(from: try downloadURL(bytes))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SpeedTestError.badResponse }
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return 0 }
        return Double(data.count) * 8 / elapsed / 1_000_000
    }

    private func measureLatency(samples: Int = 4) async throws -> Double {
        let session = makeSession()
        var best = Double.greatestFiniteMagnitude
        for _ in 0..<samples {
            let start = Date()
            _ = try await session.data(from: try downloadURL(0))
            best = min(best, Date().timeIntervalSince(start) * 1000)
        }
        return best == .greatestFiniteMagnitude ? 0 : best
    }
}
