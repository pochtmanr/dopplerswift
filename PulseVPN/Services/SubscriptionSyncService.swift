import Foundation
import RevenueCat

/// Result of a subscription sync attempt.
enum SyncResult: Sendable {
    case success
    case rejected(owner: String)
    case skipped
    case error(String)
}

/// Syncs RevenueCat subscription state to Supabase via `claim_subscription` RPC.
/// Uses raw URLSession (matching project conventions — no Supabase SDK).
///
/// The `claim_subscription` RPC enforces ownership lock:
/// - First claim → locks transaction to account
/// - Same account → updates expiry/tier
/// - Different account → REJECTS (returns `action: "rejected"`)
@MainActor
final class SubscriptionSyncService {

    private var lastSyncKey: String = ""
    private var lastSyncTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 30

    /// Call after every purchase, restore, or login.
    /// Returns the sync result so callers can handle ownership rejection.
    @discardableResult
    func sync(
        accountId: String,
        customerInfo: CustomerInfo,
        tier: SubscriptionTier
    ) async -> SyncResult {
        guard tier != .free else { return .skipped }

        let entitlementId = tier == .premium ? RCEntitlements.premium : RCEntitlements.pro
        guard let entitlement = customerInfo.entitlements.active[entitlementId] else { return .skipped }

        let productId = entitlement.productIdentifier
        let expiresAt = entitlement.expirationDate
        let dateString: String
        if let originalDate = entitlement.originalPurchaseDate {
            dateString = ISO8601DateFormatter().string(from: originalDate)
        } else {
            dateString = "unknown"
        }
        let originalTransactionId = "\(productId)_\(dateString)"

        // Throttle + deduplicate (include accountId so switching accounts always triggers a fresh sync)
        let syncKey = "\(accountId)_\(tier.rawValue)_\(expiresAt?.timeIntervalSince1970 ?? 0)_\(originalTransactionId)"
        let now = Date()
        if syncKey == lastSyncKey && now.timeIntervalSince(lastSyncTime) < throttleInterval {
            return .skipped
        }

        guard let baseURL = SupabaseConfig.url,
              let apiKey = SupabaseConfig.anonKey else {
            NSLog("[SubscriptionSync] Supabase not configured — skipping sync")
            return .error("Supabase not configured")
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/claim_subscription") else {
            NSLog("[SubscriptionSync] Invalid Supabase URL")
            return .error("Invalid URL")
        }

        let body: [String: Any?] = [
            "p_account_id": accountId,
            "p_tier": tier.rawValue,
            "p_expires_at": expiresAt.map { ISO8601DateFormatter().string(from: $0) },
            "p_original_transaction_id": originalTransactionId,
            "p_store": "app_store",
            "p_product_id": productId
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {

                // Parse the response to check for rejection
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let action = json["action"] as? String
                    let success = json["success"] as? Bool ?? false

                    if !success && action == "rejected" {
                        let owner = json["owner"] as? String ?? "unknown"
                        NSLog("[SubscriptionSync] REJECTED — subscription owned by %@", owner)
                        return .rejected(owner: owner)
                    }

                    NSLog("[SubscriptionSync] %@ (action: %@)", success ? "OK" : "FAIL", action ?? "none")
                }

                lastSyncKey = syncKey
                lastSyncTime = now
                return .success
            } else {
                NSLog("[SubscriptionSync] Non-200 response")
                return .error("Server returned non-200")
            }
        } catch {
            NSLog("[SubscriptionSync] Failed: %@", error.localizedDescription)
            return .error(error.localizedDescription)
        }
    }

    /// Verifies whether a restore is allowed for this account + transaction.
    /// Calls the `verify_restore` RPC.
    func verifyRestore(
        accountId: String,
        originalTransactionId: String
    ) async -> RestoreVerification {
        guard let baseURL = SupabaseConfig.url,
              let apiKey = SupabaseConfig.anonKey else {
            return .error("Supabase not configured")
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/verify_restore") else {
            return .error("Invalid URL")
        }

        let body: [String: String] = [
            "p_account_id": accountId,
            "p_original_transaction_id": originalTransactionId
        ]

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return .error("Server error")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .error("Invalid response")
            }

            let allowed = json["allowed"] as? Bool ?? false
            let reason = json["reason"] as? String ?? "unknown"

            if allowed {
                return .allowed
            } else {
                let owner = json["owner"] as? String ?? "unknown"
                NSLog("[SubscriptionSync] Restore rejected: %@ (owner: %@)", reason, owner)
                return .rejected(owner: owner)
            }
        } catch {
            NSLog("[SubscriptionSync] verifyRestore failed: %@", error.localizedDescription)
            return .error(error.localizedDescription)
        }
    }
}

enum RestoreVerification: Sendable {
    case allowed
    case rejected(owner: String)
    case error(String)
}
