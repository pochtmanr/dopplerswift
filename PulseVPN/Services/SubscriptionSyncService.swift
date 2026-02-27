import Foundation
import RevenueCat

/// Syncs RevenueCat subscription state to Supabase via `claim_subscription` RPC.
/// Uses raw URLSession (matching project conventions — no Supabase SDK).
/// Mirrors the React Native `syncSubscriptionToSupabase()` logic.
@MainActor
final class SubscriptionSyncService {

    private var lastSyncKey: String = ""
    private var lastSyncTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 30

    /// Call after every purchase, restore, or login.
    func sync(
        accountId: String,
        customerInfo: CustomerInfo,
        tier: SubscriptionTier
    ) async {
        guard tier != .free else { return }

        let entitlementId = tier == .premium ? RCEntitlements.premium : RCEntitlements.pro
        guard let entitlement = customerInfo.entitlements.active[entitlementId] else { return }

        let productId = entitlement.productIdentifier
        let expiresAt = entitlement.expirationDate
        let dateString: String
        if let originalDate = entitlement.originalPurchaseDate {
            dateString = ISO8601DateFormatter().string(from: originalDate)
        } else {
            dateString = "unknown"
        }
        let originalTransactionId = "\(productId)_\(dateString)"

        // Throttle + deduplicate
        let syncKey = "\(tier.rawValue)_\(expiresAt?.timeIntervalSince1970 ?? 0)_\(originalTransactionId)"
        let now = Date()
        if syncKey == lastSyncKey && now.timeIntervalSince(lastSyncTime) < throttleInterval {
            return
        }

        guard let baseURL = SupabaseConfig.url,
              let apiKey = SupabaseConfig.anonKey else {
            NSLog("[SubscriptionSync] Supabase not configured — skipping sync")
            return
        }

        guard let url = URL(string: "\(baseURL)/rest/v1/rpc/claim_subscription") else {
            NSLog("[SubscriptionSync] Invalid Supabase URL")
            return
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

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                lastSyncKey = syncKey
                lastSyncTime = now
            } else {
                NSLog("[SubscriptionSync] Non-200 response")
            }
        } catch {
            NSLog("[SubscriptionSync] Failed: %@", error.localizedDescription)
        }
    }
}
