import Foundation

// MARK: - Speed Test Result

struct SpeedTestResult: Sendable {
    let downloadMbps: Double
    let uploadMbps: Double
    let pingMs: Int
    let timestamp: Date
}

// MARK: - Speed Test Phase

enum SpeedTestPhase: Sendable, Equatable {
    case idle
    case ping
    case download
    case upload
    case complete
}

// MARK: - Speed Test Service

enum SpeedTestService {

    // MARK: - Configuration

    private static let downloadURL = "https://speed.cloudflare.com/__down?bytes=10000000"
    private static let uploadURL = "https://speed.cloudflare.com/__up"
    private static let pingURL = "https://speed.cloudflare.com/__down?bytes=0"
    private static let uploadPayloadSize = 5_000_000

    // MARK: - Public

    static func run(
        onPhaseChange: @Sendable @MainActor (SpeedTestPhase) -> Void
    ) async throws -> SpeedTestResult {
        await onPhaseChange(.ping)
        let pingMs = try await measurePing()

        await onPhaseChange(.download)
        let downloadMbps = try await measureDownload()

        await onPhaseChange(.upload)
        let uploadMbps = try await measureUpload()

        await onPhaseChange(.complete)

        return SpeedTestResult(
            downloadMbps: downloadMbps,
            uploadMbps: uploadMbps,
            pingMs: pingMs,
            timestamp: Date()
        )
    }

    // MARK: - Ping

    private static func measurePing() async throws -> Int {
        guard let url = URL(string: pingURL) else { return 0 }

        var totalMs: Double = 0
        let attempts = 3

        for _ in 0..<attempts {
            let start = CFAbsoluteTimeGetCurrent()
            let (_, _) = try await URLSession.shared.data(from: url)
            let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
            totalMs += elapsed
        }

        return Int(totalMs / Double(attempts))
    }

    // MARK: - Download

    private static func measureDownload() async throws -> Double {
        guard let url = URL(string: downloadURL) else { return 0 }

        let start = CFAbsoluteTimeGetCurrent()
        let (data, _) = try await URLSession.shared.data(from: url)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard elapsed > 0 else { return 0 }

        let bits = Double(data.count) * 8
        let megabits = bits / 1_000_000
        return megabits / elapsed
    }

    // MARK: - Upload

    private static func measureUpload() async throws -> Double {
        guard let url = URL(string: uploadURL) else { return 0 }

        let payload = Data(count: uploadPayloadSize)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let start = CFAbsoluteTimeGetCurrent()
        let (_, _) = try await URLSession.shared.upload(for: request, from: payload)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        guard elapsed > 0 else { return 0 }

        let bits = Double(uploadPayloadSize) * 8
        let megabits = bits / 1_000_000
        return megabits / elapsed
    }
}
