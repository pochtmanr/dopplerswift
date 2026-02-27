import Foundation

/// Shared configuration store backed by App Group UserDefaults.
/// Used by both the main app and the packet tunnel extension.
enum ConfigStore {

    // MARK: - Constants

    private static let appGroupID = "group.com.pulsingroutes.vpn"

    private enum Key {
        static let xrayConfigJSON = "xray_config_json"
        static let savedServers = "saved_servers"
        static let selectedServerID = "selected_server_id"
        static let smartRoutingEnabled = "smart_routing_enabled"
        static let smartRoutingCountry = "smart_routing_country"
        static let smartRoutingCustomDomains = "smart_routing_custom_domains"
        static let bypassTLDWebsites = "bypass_tld_websites"
        static let bypassGovernmentBanking = "bypass_government_banking"
        static let bypassStreamingMedia = "bypass_streaming_media"
        static let bypassEcommerce = "bypass_ecommerce"
    }

    // MARK: - Shared Defaults

    static var sharedDefaults: UserDefaults? {
        let defaults = UserDefaults(suiteName: appGroupID)
        if defaults == nil {
            NSLog("[ConfigStore] ERROR: App Group '\(appGroupID)' not available")
        }
        return defaults
    }

    // MARK: - Xray Config

    static func saveXrayConfig(_ json: String) {
        sharedDefaults?.set(json, forKey: Key.xrayConfigJSON)
    }

    static func loadXrayConfig() -> String? {
        sharedDefaults?.string(forKey: Key.xrayConfigJSON)
    }

    // MARK: - Servers

    static func saveServers(_ servers: [ServerConfig]) {
        do {
            let data = try JSONEncoder().encode(servers)
            sharedDefaults?.set(data, forKey: Key.savedServers)
        } catch {
            NSLog("[ConfigStore] Failed to encode servers: \(error)")
        }
    }

    static func loadServers() -> [ServerConfig] {
        guard let data = sharedDefaults?.data(forKey: Key.savedServers) else {
            return []
        }
        do {
            return try JSONDecoder().decode([ServerConfig].self, from: data)
        } catch {
            NSLog("[ConfigStore] Failed to decode servers: \(error)")
            return []
        }
    }

    // MARK: - Selected Server

    static func saveSelectedServerID(_ id: UUID?) {
        sharedDefaults?.set(id?.uuidString, forKey: Key.selectedServerID)
    }

    static func loadSelectedServerID() -> UUID? {
        guard let string = sharedDefaults?.string(forKey: Key.selectedServerID) else {
            return nil
        }
        return UUID(uuidString: string)
    }

    // MARK: - Smart Routing

    static func saveSmartRoutingEnabled(_ enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: Key.smartRoutingEnabled)
    }

    static func loadSmartRoutingEnabled() -> Bool {
        sharedDefaults?.bool(forKey: Key.smartRoutingEnabled) ?? false
    }

    static func saveSmartRoutingCountry(_ code: String) {
        sharedDefaults?.set(code, forKey: Key.smartRoutingCountry)
    }

    static func loadSmartRoutingCountry() -> String? {
        sharedDefaults?.string(forKey: Key.smartRoutingCountry)
    }

    static func saveSmartRoutingCustomDomains(_ domains: [String]) {
        sharedDefaults?.set(domains, forKey: Key.smartRoutingCustomDomains)
    }

    static func loadSmartRoutingCustomDomains() -> [String] {
        sharedDefaults?.stringArray(forKey: Key.smartRoutingCustomDomains) ?? []
    }

    // MARK: - Bypass Categories

    static func saveBypassCategory(_ key: String, enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: key)
    }

    static func loadBypassTLDWebsites() -> Bool {
        sharedDefaults?.object(forKey: Key.bypassTLDWebsites) as? Bool ?? true
    }

    static func loadBypassGovernmentBanking() -> Bool {
        sharedDefaults?.object(forKey: Key.bypassGovernmentBanking) as? Bool ?? true
    }

    static func loadBypassStreamingMedia() -> Bool {
        sharedDefaults?.object(forKey: Key.bypassStreamingMedia) as? Bool ?? true
    }

    static func loadBypassEcommerce() -> Bool {
        sharedDefaults?.object(forKey: Key.bypassEcommerce) as? Bool ?? true
    }

    static func saveBypassTLDWebsites(_ enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: Key.bypassTLDWebsites)
    }

    static func saveBypassGovernmentBanking(_ enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: Key.bypassGovernmentBanking)
    }

    static func saveBypassStreamingMedia(_ enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: Key.bypassStreamingMedia)
    }

    static func saveBypassEcommerce(_ enabled: Bool) {
        sharedDefaults?.set(enabled, forKey: Key.bypassEcommerce)
    }
}
