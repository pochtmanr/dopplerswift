import Foundation

// MARK: - Traceroute Service

/// Calls the server-side MTR API to trace the route from the VPS to a target host.
/// Returns all hops at once (not streamed) since the server runs a full MTR report.
final class TracerouteService: Sendable {

    enum TracerouteError: LocalizedError {
        case missingConfig
        case invalidURL
        case unauthorized
        case serverError(Int, String?)
        case decodingFailed

        var errorDescription: String? {
            switch self {
            case .missingConfig: return "Traceroute API not configured"
            case .invalidURL: return "Invalid traceroute API URL"
            case .unauthorized: return "Traceroute API auth failed"
            case .serverError(let code, let msg): return "Server error \(code): \(msg ?? "unknown")"
            case .decodingFailed: return "Failed to parse trace response"
            }
        }
    }

    // MARK: - Config from Info.plist

    private static var apiURL: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TRACEROUTE_API_URL") as? String,
              !value.isEmpty,
              value != "$(TRACEROUTE_API_URL)" else {
            return nil
        }
        return value
    }

    private static var apiToken: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "TRACEROUTE_API_TOKEN") as? String,
              !value.isEmpty,
              value != "$(TRACEROUTE_API_TOKEN)" else {
            return nil
        }
        return value
    }

    // MARK: - Public

    /// Runs a server-side MTR trace to the given host and returns all hops.
    func trace(host: String) async throws -> [TraceHop] {
        guard let baseURL = Self.apiURL, let token = Self.apiToken else {
            throw TracerouteError.missingConfig
        }

        guard var components = URLComponents(string: baseURL) else {
            throw TracerouteError.invalidURL
        }

        components.path = "/api/trace"
        components.queryItems = [URLQueryItem(name: "target", value: host)]

        guard let url = components.url else {
            throw TracerouteError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        NSLog("[Traceroute] Requesting trace to %@ via API", host)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TracerouteError.serverError(0, "Not an HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 401 {
                throw TracerouteError.unauthorized
            }
            throw TracerouteError.serverError(httpResponse.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(TraceResponse.self, from: data)

        NSLog("[Traceroute] Received %d hops for %@", decoded.hops.count, host)

        return decoded.hops.map { hop in
            TraceHop(
                hopNumber: hop.hopNumber,
                ip: hop.ip,
                latency: hop.latency,
                loss: hop.loss
            )
        }
    }
}

// MARK: - API Response Models

private struct TraceResponse: Decodable {
    let hops: [TraceResponseHop]
    let target: String
}

private struct TraceResponseHop: Decodable {
    let hopNumber: Int
    let ip: String?
    let latency: Double?
    let loss: Double?
}
