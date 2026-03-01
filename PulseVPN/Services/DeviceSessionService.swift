import Foundation

// MARK: - Device Session Model

struct DeviceSession: Identifiable, Sendable {
    let id: UUID
    let accountId: UUID
    let deviceId: String
    let deviceName: String
    let deviceType: String
    let isMain: Bool
    let lastActiveAt: Date
    let createdAt: Date

    var typeIcon: String {
        switch deviceType {
        case "ios": return "iphone"
        case "android": return "smartphone"
        case "macos": return "laptopcomputer"
        case "chrome": return "globe"
        case "firefox": return "globe"
        case "web": return "desktopcomputer"
        default: return "desktopcomputer"
        }
    }

    var typeDisplayName: String {
        switch deviceType {
        case "ios": return "iOS"
        case "android": return "Android"
        case "macos": return "macOS"
        case "chrome": return "Chrome"
        case "firefox": return "Firefox"
        case "web": return "Web"
        default: return deviceType.capitalized
        }
    }
}

// MARK: - Device Session Service

enum DeviceSessionService {

    /// Fetches all device sessions for the given account via `get_account_devices` RPC.
    static func fetchDevices(accountId: String) async throws -> [DeviceSession] {
        let data = try await supabaseRPC(
            function: "get_account_devices",
            body: ["p_account_id": accountId]
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DeviceSessionError.decodingError("Response is not a JSON object")
        }

        guard json["success"] as? Bool == true else {
            let errorMsg = json["error"] as? String ?? "Unknown error"
            throw DeviceSessionError.serverError(errorMsg)
        }

        guard let devicesJSON = json["devices"] as? [[String: Any]] else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: dateString) { return date }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ", "yyyy-MM-dd'T'HH:mm:ssZZZZZ", "yyyy-MM-dd'T'HH:mm:ss"] {
                formatter.dateFormat = fmt
                if let date = formatter.date(from: dateString) { return date }
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }

        return devicesJSON.compactMap { deviceDict in
            guard let deviceData = try? JSONSerialization.data(withJSONObject: deviceDict) else { return nil }

            struct RawDevice: Decodable {
                let id: UUID
                let account_id: UUID // swiftlint:disable:this identifier_name
                let device_id: String // swiftlint:disable:this identifier_name
                let device_name: String // swiftlint:disable:this identifier_name
                let device_type: String // swiftlint:disable:this identifier_name
                let is_main: Bool // swiftlint:disable:this identifier_name
                let last_active_at: Date // swiftlint:disable:this identifier_name
                let created_at: Date // swiftlint:disable:this identifier_name
            }

            guard let raw = try? decoder.decode(RawDevice.self, from: deviceData) else { return nil }
            return DeviceSession(
                id: raw.id,
                accountId: raw.account_id,
                deviceId: raw.device_id,
                deviceName: raw.device_name,
                deviceType: raw.device_type,
                isMain: raw.is_main,
                lastActiveAt: raw.last_active_at,
                createdAt: raw.created_at
            )
        }
    }

    /// Removes a device session via `remove_device` RPC.
    static func removeDevice(accountId: String, deviceId: String) async throws {
        let data = try await supabaseRPC(
            function: "remove_device",
            body: ["p_account_id": accountId, "p_device_id": deviceId]
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["success"] as? Bool == true else {
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "Failed to remove device"
            throw DeviceSessionError.serverError(errorMsg)
        }
    }

    // MARK: - Private

    private static func supabaseRPC(function: String, body: [String: String]) async throws -> Data {
        guard let baseURL = SupabaseConfig.url,
              let apiKey = SupabaseConfig.anonKey else {
            throw DeviceSessionError.notConfigured
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/\(function)") else {
            throw DeviceSessionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw DeviceSessionError.serverError("HTTP \(httpResponse.statusCode): \(responseBody)")
        }

        return data
    }
}

// MARK: - Errors

enum DeviceSessionError: LocalizedError {
    case notConfigured
    case invalidURL
    case serverError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured."
        case .invalidURL:
            return "Invalid Supabase URL."
        case .serverError(let msg):
            return msg
        case .decodingError(let msg):
            return "Failed to decode devices: \(msg)"
        }
    }
}
