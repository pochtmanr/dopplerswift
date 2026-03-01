import Foundation
#if os(iOS)
import UIKit
#endif

// MARK: - Account Model

struct Account: Codable, Sendable {
    let id: UUID
    let accountId: String
    let subscriptionTier: String
    let maxDevices: Int
    let createdAt: Date
    let updatedAt: Date?
    let contactMethod: String?
    let contactValue: String?

    enum CodingKeys: String, CodingKey {
        case id
        case accountId = "account_id"
        case subscriptionTier = "subscription_tier"
        case maxDevices = "max_devices"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case contactMethod = "contact_method"
        case contactValue = "contact_value"
    }

    var isPro: Bool { subscriptionTier == "pro" || subscriptionTier == "premium" }
    var isPremium: Bool { subscriptionTier == "premium" }
    var hasLinkedContact: Bool { contactMethod != nil && contactValue != nil }
}

// MARK: - Contact Method

enum ContactMethod: String, CaseIterable, Identifiable {
    case telegram
    case whatsapp
    case email

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .telegram: "Telegram"
        case .whatsapp: "WhatsApp"
        case .email: "Email"
        }
    }

    var localizedLabel: String {
        String(localized: label)
    }

    var icon: String {
        switch self {
        case .telegram: "paperplane.fill"
        case .whatsapp: "phone.fill"
        case .email: "envelope.fill"
        }
    }

    var placeholder: LocalizedStringResource {
        switch self {
        case .telegram: "@username"
        case .whatsapp: "+1234567890"
        case .email: "you@example.com"
        }
    }

    #if os(iOS)
    var keyboardType: UIKeyboardType {
        switch self {
        case .telegram: .default
        case .whatsapp: .phonePad
        case .email: .emailAddress
        }
    }
    #endif

    func validate(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch self {
        case .telegram:
            return trimmed.count >= 2
        case .whatsapp:
            let digits = trimmed.filter(\.isNumber)
            return digits.count >= 7
        case .email:
            return trimmed.contains("@") && trimmed.contains(".")
        }
    }
}

// MARK: - Errors

enum AccountError: LocalizedError {
    case supabaseNotConfigured
    case invalidURL
    case invalidAccountIdFormat
    case networkError(String)
    case serverError(Int, String)
    case decodingError(String)
    case accountNotFound

    var errorDescription: String? {
        switch self {
        case .supabaseNotConfigured:
            return "Supabase is not configured. Check SUPABASE_URL and SUPABASE_ANON_KEY in Info.plist."
        case .invalidURL:
            return "Invalid Supabase URL configuration."
        case .invalidAccountIdFormat:
            return "Account ID must match format VPN-XXXX-XXXX-XXXX."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .decodingError(let reason):
            return "Failed to decode account data: \(reason)"
        case .accountNotFound:
            return "No account found with that ID."
        }
    }
}

// MARK: - Account Manager

@Observable
final class AccountManager {

    // MARK: - Public Properties

    private(set) var account: Account?
    private(set) var isLoading = false
    private(set) var isInitializing = true
    var errorMessage: String?

    var isAuthenticated: Bool { account != nil }

    var isOnboardingComplete: Bool = UserDefaults.standard.bool(forKey: Keys.onboardingComplete) {
        didSet { UserDefaults.standard.set(isOnboardingComplete, forKey: Keys.onboardingComplete) }
    }

    // MARK: - Private Properties

    private enum Keys {
        static let accountId = "doppler_account_id"
        static let onboardingComplete = "doppler_onboarding_complete"
        static let macDeviceId = "doppler_device_id"
        static let prefillAccountId = "doppler_prefill_account_id"
    }

    /// Account ID to pre-fill on the login screen after a subscription ownership redirect.
    /// Consumed once by AccountSetupView, then cleared.
    var prefillAccountId: String? {
        get { UserDefaults.standard.string(forKey: Keys.prefillAccountId) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.prefillAccountId) }
    }

    /// Clears the prefill key (call after reading it in AccountSetupView).
    func consumePrefillAccountId() -> String? {
        guard let id = prefillAccountId else { return nil }
        prefillAccountId = nil
        return id
    }

    // MARK: - Public Methods

    /// Called on app launch to restore a previously authenticated session.
    func initialize() async {
        defer { isInitializing = false }

        guard let storedAccountId = UserDefaults.standard.string(forKey: Keys.accountId) else {
            return
        }

        guard AccountInputFormatter.isValid(storedAccountId) else {
            UserDefaults.standard.removeObject(forKey: Keys.accountId)
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let account = try await registerDevice(accountId: storedAccountId)
            self.account = account
        } catch {
            NSLog("[AccountManager] Failed to restore session: %@", error.localizedDescription)
            // Keep the stored account_id so the user can retry on next launch
            errorMessage = error.localizedDescription
        }
    }

    /// Creates a brand-new account via the `create_account` RPC, then registers this device.
    func createAccount() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let accountId = try await callCreateAccount()
            let account = try await registerDevice(accountId: accountId)
            self.account = account
            UserDefaults.standard.set(accountId, forKey: Keys.accountId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Logs in with an existing account ID (entered manually by the user).
    func loginWithAccountId(_ id: String) async {
        let formatted = AccountInputFormatter.format(id)

        guard AccountInputFormatter.isValid(formatted) else {
            errorMessage = AccountError.invalidAccountIdFormat.errorDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let account = try await registerDevice(accountId: formatted)
            self.account = account
            UserDefaults.standard.set(formatted, forKey: Keys.accountId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the account on the server, then clears local state.
    func deleteAccount() async throws {
        guard let account else {
            throw AccountError.accountNotFound
        }

        let body: [String: String] = [
            "p_account_id": account.accountId
        ]

        let data = try await supabaseRPC(function: "delete_account", body: body)

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["success"] as? Bool != true {
            let errorMsg = json["error"] as? String ?? "Failed to delete account"
            throw AccountError.networkError(errorMsg)
        }

        logout()
    }

    /// Links a contact method to the account for recovery purposes.
    func linkContact(method: ContactMethod, value: String) async throws {
        guard let account else {
            throw AccountError.accountNotFound
        }

        let body: [String: String] = [
            "p_account_id": account.accountId,
            "p_contact_method": method.rawValue,
            "p_contact_value": value.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        let data = try await supabaseRPC(function: "link_contact", body: body)

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["success"] as? Bool != true {
            let errorMsg = json["error"] as? String ?? "Failed to link contact"
            throw AccountError.networkError(errorMsg)
        }

        // Re-fetch account to get updated contact info
        let refreshed = try await registerDevice(accountId: account.accountId)
        self.account = refreshed
    }

    /// Clears all local auth state and resets onboarding.
    func logout() {
        account = nil
        errorMessage = nil
        isOnboardingComplete = false
        UserDefaults.standard.removeObject(forKey: Keys.accountId)
    }

    /// Clears local auth state but keeps onboarding complete.
    /// Use when switching accounts (e.g. from subscription conflict dialog)
    /// so the user goes straight to the login screen instead of Welcome.
    func switchAccount() {
        account = nil
        errorMessage = nil
        // Keep isOnboardingComplete = true to skip WelcomeView
        UserDefaults.standard.removeObject(forKey: Keys.accountId)
    }

    // MARK: - Private: RPC Calls

    private func callCreateAccount() async throws -> String {
        let data = try await supabaseRPC(function: "create_account", body: nil)
        let rawResponse = String(data: data, encoding: .utf8) ?? ""
        NSLog("[AccountManager] create_account raw response: %@", rawResponse)

        struct CreateAccountResponse: Decodable {
            let account_id: String // swiftlint:disable:this identifier_name
        }

        // Try object: {"account_id": "VPN-XXXX-XXXX-XXXX"}
        if let response = try? JSONDecoder().decode(CreateAccountResponse.self, from: data) {
            return response.account_id
        }

        // Try plain string: "VPN-XXXX-XXXX-XXXX"
        if let plainString = try? JSONDecoder().decode(String.self, from: data),
           AccountInputFormatter.isValid(plainString) {
            return plainString
        }

        // Try quoted string without JSON wrapper
        let trimmed = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        if AccountInputFormatter.isValid(trimmed) {
            return trimmed
        }

        throw AccountError.decodingError("Unexpected response format: \(rawResponse)")
    }

    private func registerDevice(accountId: String) async throws -> Account {
        let body: [String: String] = [
            "p_account_id": accountId,
            "p_device_id": deviceId,
            "p_device_name": deviceName,
            "p_device_type": deviceType
        ]

        let data = try await supabaseRPC(function: "register_device", body: body)

        // register_device returns: { success, error?, account: { id, account_id, ... }, session: {...} }
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw AccountError.decodingError("Response is not a JSON object")
            }

            guard json["success"] as? Bool == true else {
                let errorMsg = json["error"] as? String ?? "Unknown error"
                if errorMsg.contains("not found") {
                    throw AccountError.accountNotFound
                }
                throw AccountError.networkError(errorMsg)
            }

            guard let accountJSON = json["account"] else {
                throw AccountError.decodingError("Missing 'account' in response")
            }

            let accountData = try JSONSerialization.data(withJSONObject: accountJSON)
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
            return try decoder.decode(Account.self, from: accountData)
        } catch let error as AccountError {
            throw error
        } catch {
            throw AccountError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Private: Networking

    private func supabaseRPC(function: String, body: [String: String]?) async throws -> Data {
        guard let baseURL = SupabaseConfig.url,
              let apiKey = SupabaseConfig.anonKey else {
            throw AccountError.supabaseNotConfigured
        }

        let urlString = "\(baseURL)/rest/v1/rpc/\(function)"

        guard let url = URL(string: urlString) else {
            throw AccountError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            request.httpBody = Data("{}".utf8)
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AccountError.networkError(error.localizedDescription)
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw AccountError.serverError(httpResponse.statusCode, responseBody)
        }

        return data
    }

    // MARK: - Private: Device Info

    private var deviceId: String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        if let stored = UserDefaults.standard.string(forKey: Keys.macDeviceId) {
            return stored
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: Keys.macDeviceId)
        return newId
        #endif
    }

    private var deviceName: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }

    private var deviceType: String {
        #if os(iOS)
        return "ios"
        #else
        return "macos"
        #endif
    }
}
