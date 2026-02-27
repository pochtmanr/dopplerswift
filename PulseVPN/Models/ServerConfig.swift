import Foundation

// MARK: - Server Source

/// Indicates where a server configuration came from.
enum ServerSource: String, Codable, Sendable {
    case manual       // User pasted vless:// URI or subscription
    case cloud        // Fetched from Supabase
}

// MARK: - Server Config

struct ServerConfig: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let vlessConfig: VLessConfig
    var isSelected: Bool
    let source: ServerSource

    // Optional metadata from Supabase for cloud servers
    var name: String?
    var supabaseID: UUID?
    var country: String?
    var countryCode: String?
    var city: String?
    var loadPercentage: Int?
    var isPremium: Bool?
    var latencyMs: Int?
    var speedMbps: Double?

    init(
        vlessConfig: VLessConfig,
        isSelected: Bool = false,
        source: ServerSource = .manual,
        name: String? = nil,
        supabaseID: UUID? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        city: String? = nil,
        loadPercentage: Int? = nil,
        isPremium: Bool? = nil,
        latencyMs: Int? = nil,
        speedMbps: Double? = nil
    ) {
        self.id = vlessConfig.id
        self.vlessConfig = vlessConfig
        self.isSelected = isSelected
        self.source = source
        self.name = name
        self.supabaseID = supabaseID
        self.country = country
        self.countryCode = countryCode
        self.city = city
        self.loadPercentage = loadPercentage
        self.isPremium = isPremium
        self.latencyMs = latencyMs
        self.speedMbps = speedMbps
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return vlessConfig.remark.isEmpty ? vlessConfig.address : vlessConfig.remark
    }

    /// Country flag emoji from the country code.
    var flagEmoji: String {
        guard let code = countryCode else { return "" }
        let twoChar = String(code.prefix(2)).uppercased()
        let base: UInt32 = 127397
        return twoChar.unicodeScalars.compactMap {
            UnicodeScalar(base + $0.value)
        }.map { String($0) }.joined()
    }

    /// Subtitle text showing location or address info.
    var subtitle: String {
        if let city, let country {
            return "\(city), \(country)"
        }
        return "\(vlessConfig.address):\(vlessConfig.port)"
    }
}
