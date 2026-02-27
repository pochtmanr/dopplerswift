import Foundation

// MARK: - Supabase Server Model

/// Represents a VPN server fetched from the Supabase `vpn_servers` table.
/// Only includes public-facing columns -- no credentials or admin data.
struct SupabaseServer: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let country: String
    let countryCode: String
    let city: String
    let ipAddress: String
    let port: Int?
    let `protocol`: String?
    let configData: String?
    let loadPercentage: Int?
    let isPremium: Bool?
    let latencyMs: Int?
    let isActive: Bool?
    let speedMbps: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, country, city, port, `protocol`
        case countryCode = "country_code"
        case ipAddress = "ip_address"
        case configData = "config_data"
        case loadPercentage = "load_percentage"
        case isPremium = "is_premium"
        case latencyMs = "latency_ms"
        case isActive = "is_active"
        case speedMbps = "speed_mbps"
    }

    /// Country flag emoji derived from the country code (first two chars).
    var flagEmoji: String {
        let code = String(countryCode.prefix(2)).uppercased()
        let base: UInt32 = 127397
        return code.unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }.map { String($0) }.joined()
    }

    /// Human-readable location string.
    var locationDisplay: String {
        "\(city), \(country)"
    }
}

// MARK: - Supabase Configuration

/// Reads Supabase config from the app's Info.plist.
///
/// Add these keys to your Info.plist (or xcconfig / build settings):
///   - SUPABASE_URL (String) -- e.g. "https://yourproject.supabase.co"
///   - SUPABASE_ANON_KEY (String) -- your project's anon/public key
///
/// If these are not set, cloud server fetching will be disabled (not crash).
enum SupabaseConfig {
    static var url: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !value.isEmpty,
              value != "$(SUPABASE_URL)" else {
            return nil
        }
        return value
    }

    static var anonKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !value.isEmpty,
              value != "$(SUPABASE_ANON_KEY)" else {
            return nil
        }
        return value
    }

    static var isConfigured: Bool {
        url != nil && anonKey != nil
    }
}

// MARK: - Service Errors

enum SupabaseServerError: LocalizedError {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case noServers

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Supabase URL configuration."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .decodingError(let reason):
            return "Failed to decode servers: \(reason)"
        case .noServers:
            return "No active servers found."
        }
    }
}

// MARK: - Server Service

/// Fetches the list of active VPN servers from Supabase REST API.
/// Uses only the anon key (public access via RLS policy).
/// Does NOT fetch sensitive columns (config_data, marzban_*).
enum SupabaseServerService {

    /// Columns to select -- excludes credentials and admin data.
    private static let selectColumns = "id,name,country,country_code,city,ip_address,port,protocol,config_data,load_percentage,is_premium,latency_ms,is_active,speed_mbps"

    /// Fetches all active servers from `vpn_servers` table.
    /// Returns empty array if Supabase is not configured.
    static func fetchServers() async throws -> [SupabaseServer] {
        guard let baseURL = SupabaseConfig.url,
              let apiKey = SupabaseConfig.anonKey else {
            NSLog("[SupabaseServerService] Supabase not configured. Set SUPABASE_URL and SUPABASE_ANON_KEY in Info.plist.")
            return []
        }

        let urlString = "\(baseURL)/rest/v1/vpn_servers?select=\(selectColumns)&is_active=eq.true&order=country.asc,name.asc"

        guard let url = URL(string: urlString) else {
            throw SupabaseServerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw SupabaseServerError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw SupabaseServerError.networkError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let decoder = JSONDecoder()
            let servers = try decoder.decode([SupabaseServer].self, from: data)
            return servers
        } catch {
            throw SupabaseServerError.decodingError(error.localizedDescription)
        }
    }
}
