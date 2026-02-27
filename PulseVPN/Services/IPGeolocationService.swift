import Foundation

// MARK: - IP Geolocation Errors

enum IPGeolocationError: LocalizedError {
    case invalidURL
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid geolocation URL."
        case .networkError(let reason):
            return "Geolocation network error: \(reason)"
        case .decodingError(let reason):
            return "Failed to decode geolocation: \(reason)"
        }
    }
}

// MARK: - IP Geolocation Service

/// Fetches IP geolocation data from ipapi.co (HTTPS, no API key, 1000 req/day).
enum IPGeolocationService {

    private static let baseURL = "https://ipapi.co"

    /// In-memory cache: URL string → (result, timestamp)
    private static var cache: [String: (geo: IPGeolocation, date: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300 // 5 minutes

    /// Fetches geolocation for the device's current public IP.
    static func fetchCurrentIP() async throws -> IPGeolocation {
        try await fetch(urlString: "\(baseURL)/json/")
    }

    /// Fetches geolocation for a specific IP address.
    static func fetch(for ip: String) async throws -> IPGeolocation {
        try await fetch(urlString: "\(baseURL)/\(ip)/json/")
    }

    private static func fetch(urlString: String) async throws -> IPGeolocation {
        // Return cached result if fresh
        if let cached = cache[urlString],
           Date().timeIntervalSince(cached.date) < cacheTTL {
            return cached.geo
        }

        guard let url = URL(string: urlString) else {
            throw IPGeolocationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Retry once on 429 after a short delay
        for attempt in 0..<2 {
            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw IPGeolocationError.networkError(error.localizedDescription)
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    if attempt == 0 {
                        try? await Task.sleep(for: .seconds(3))
                        continue
                    }
                    throw IPGeolocationError.networkError("HTTP 429 — rate limited")
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    throw IPGeolocationError.networkError("HTTP \(httpResponse.statusCode)")
                }

                do {
                    let geo = try JSONDecoder().decode(IPGeolocation.self, from: data)
                    cache[urlString] = (geo, Date())
                    return geo
                } catch {
                    throw IPGeolocationError.decodingError(error.localizedDescription)
                }
            }
        }

        throw IPGeolocationError.networkError("Unexpected response")
    }
}
