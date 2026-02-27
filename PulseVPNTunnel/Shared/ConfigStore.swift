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

}
