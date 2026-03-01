import Foundation

// MARK: - IP Geolocation Errors

enum IPGeolocationError: LocalizedError {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case apiFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid geolocation URL."
        case .networkError(let reason):
            return "Geolocation network error: \(reason)"
        case .decodingError(let reason):
            return "Failed to decode geolocation: \(reason)"
        case .apiFailed(let reason):
            return "Geolocation API error: \(reason)"
        }
    }
}

// MARK: - IP Geolocation Service

/// Fetches IP geolocation data from ipwho.is (HTTPS, no API key, 10000 req/month).
/// Includes in-flight deduplication, memory + disk cache, and rate limiting.
enum IPGeolocationService {

    // ipwho.is: free HTTPS, no API key, generous rate limits
    private static let baseURL = "https://ipwho.is"

    /// In-memory cache: cache key → (result, timestamp)
    private static var cache: [String: (geo: IPGeolocation, date: Date)] = [:]
    private static let cacheTTL: TimeInterval = 300 // 5 minutes

    /// In-flight requests: cache key → Task, to deduplicate concurrent fetches
    private static var inFlight: [String: Task<IPGeolocation, Error>] = [:]

    /// Global rate limit: minimum interval between API requests
    private static var lastRequestTime: Date = .distantPast
    private static let minRequestInterval: TimeInterval = 1.5

    /// Fetches geolocation for the device's current public IP.
    static func fetchCurrentIP() async throws -> IPGeolocation {
        try await fetch(key: "currentIP", urlString: baseURL)
    }

    /// Fetches geolocation for a specific IP address.
    static func fetch(for ip: String) async throws -> IPGeolocation {
        try await fetch(key: ip, urlString: "\(baseURL)/\(ip)")
    }

    private static func fetch(key: String, urlString: String) async throws -> IPGeolocation {
        // 1. Return memory-cached result if fresh
        if let cached = cache[key],
           Date().timeIntervalSince(cached.date) < cacheTTL {
            return cached.geo
        }

        // 2. Check disk cache (survives app restarts)
        if let diskCached = loadFromDisk(key: key) {
            cache[key] = (diskCached, Date())
            return diskCached
        }

        // 3. Deduplicate: if a request for this key is already in flight, await it
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<IPGeolocation, Error> {
            defer { inFlight[key] = nil }

            // Global rate limiting: wait if we recently made a request
            let elapsed = Date().timeIntervalSince(lastRequestTime)
            if elapsed < minRequestInterval {
                try await Task.sleep(for: .seconds(minRequestInterval - elapsed))
            }

            guard let url = URL(string: urlString) else {
                throw IPGeolocationError.invalidURL
            }

            lastRequestTime = Date()

            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await URLSession.shared.data(from: url)
            } catch {
                throw IPGeolocationError.networkError(error.localizedDescription)
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 429 {
                    throw IPGeolocationError.networkError("HTTP 429 — rate limited")
                }
                if !(200...299).contains(httpResponse.statusCode) {
                    throw IPGeolocationError.networkError("HTTP \(httpResponse.statusCode)")
                }
            }

            // ipwho.is returns {"success":false,"message":"..."} on errors
            if let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = raw["success"] as? Bool, !success {
                let message = raw["message"] as? String ?? "unknown"
                throw IPGeolocationError.apiFailed(message)
            }

            do {
                let geo = try JSONDecoder().decode(IPGeolocation.self, from: data)
                cache[key] = (geo, Date())
                saveToDisk(key: key, data: data)
                return geo
            } catch {
                throw IPGeolocationError.decodingError(error.localizedDescription)
            }
        }

        inFlight[key] = task
        return try await task.value
    }

    // MARK: - Disk Cache

    private static let diskCacheTTL: TimeInterval = 3600 // 1 hour

    private static func cacheDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("geo_cache", isDirectory: true)
    }

    private static func saveToDisk(key: String, data: Data) {
        guard let dir = cacheDirectory() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)
        try? data.write(to: file)
    }

    private static func loadFromDisk(key: String) -> IPGeolocation? {
        guard let dir = cacheDirectory() else { return nil }
        let file = dir.appendingPathComponent(key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key)

        guard FileManager.default.fileExists(atPath: file.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < diskCacheTTL,
              let data = try? Data(contentsOf: file)
        else { return nil }

        return try? JSONDecoder().decode(IPGeolocation.self, from: data)
    }
}
