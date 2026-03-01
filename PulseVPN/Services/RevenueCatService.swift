import Foundation
import RevenueCat
import Observation
import SwiftUI

// MARK: - RevenueCat Configuration

enum RevenueCatConfig {
    static var apiKey: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_IOS_API_KEY") as? String,
              !value.isEmpty,
              value != "$(REVENUECAT_IOS_API_KEY)" else {
            return nil
        }
        return value
    }

    static var isConfigured: Bool { apiKey != nil }
}

// MARK: - RevenueCat Service

@MainActor
@Observable
final class RevenueCatService {

    // MARK: - State

    private(set) var customerInfo: CustomerInfo?
    private(set) var packages: [SubscriptionPackage] = []
    private(set) var isTrialEligible: Bool = false
    private(set) var trialDays: Int = 0
    private(set) var isLoading: Bool = false
    private(set) var error: String?
    private(set) var isConfigured: Bool = false

    /// When true, Supabase has rejected this account's claim to the RC subscription.
    /// Overrides RC's entitlement display — the app shows Free despite RC showing Pro.
    /// Set by sync flow when claim_subscription returns "rejected".
    /// Cleared on logout or successful claim.
    /// Persisted to UserDefaults so a force-quit doesn't reset to Pro.
    private(set) var subscriptionRejectedByServer: Bool = UserDefaults.standard.bool(forKey: "doppler_sub_rejected") {
        didSet { UserDefaults.standard.set(subscriptionRejectedByServer, forKey: "doppler_sub_rejected") }
    }

    /// The account ID that actually owns the subscription (set when rejected).
    /// Persisted to survive force-quit.
    private(set) var rejectedOwnerAccountId: String? = UserDefaults.standard.string(forKey: "doppler_sub_rejected_owner") {
        didSet { UserDefaults.standard.set(rejectedOwnerAccountId, forKey: "doppler_sub_rejected_owner") }
    }

    // MARK: - Computed

    var currentTier: SubscriptionTier {
        determineTier(from: customerInfo)
    }

    var monthlyPackage: SubscriptionPackage? {
        packages.first { $0.period == .monthly }
    }

    var sixMonthPackage: SubscriptionPackage? {
        packages.first { $0.period == .sixMonth }
    }

    var yearlyPackage: SubscriptionPackage? {
        packages.first { $0.period == .annual }
    }

    var savingsPercentage: Int {
        guard let monthly = monthlyPackage, let yearly = yearlyPackage else { return 0 }
        let monthlyAnnualized = monthly.price * 12
        guard monthlyAnnualized > 0 else { return 0 }
        let savings = (monthlyAnnualized - yearly.price) / monthlyAnnualized * 100
        return Int(truncating: savings as NSDecimalNumber)
    }

    var activeEntitlement: EntitlementInfo? {
        let entitlements = customerInfo?.entitlements.active
        return entitlements?[RCEntitlements.premium] ?? entitlements?[RCEntitlements.pro]
    }

    var expirationDate: Date? {
        activeEntitlement?.expirationDate
    }

    var isInGracePeriod: Bool {
        activeEntitlement?.billingIssueDetectedAt != nil
    }

    var isPro: Bool { currentTier >= .pro }
    var isPremium: Bool { currentTier >= .premium }

    /// Returns the effective tier considering RevenueCat, server rejection, and Supabase fallback.
    /// Supabase is the authority — if the server rejected this account's claim, tier is forced to `.free`
    /// even though RC still shows an active entitlement (Apple ID cache).
    func effectiveTier(fallbackAccount: Account?) -> SubscriptionTier {
        // Server rejection overrides everything — this account doesn't own the subscription
        if subscriptionRejectedByServer { return .free }

        let rcTier = currentTier
        guard rcTier == .free, let account = fallbackAccount else { return rcTier }
        if account.isPremium { return .premium }
        if account.isPro { return .pro }
        return .free
    }

    /// Convenience: whether user has Pro or higher considering Supabase fallback.
    func isEffectivelyPro(fallbackAccount: Account?) -> Bool {
        effectiveTier(fallbackAccount: fallbackAccount) >= .pro
    }

    /// Called when Supabase rejects this account's subscription claim.
    func markSubscriptionRejected(owner: String) {
        subscriptionRejectedByServer = true
        rejectedOwnerAccountId = owner
    }

    /// Clears the rejection state (on logout or successful claim).
    func clearSubscriptionRejection() {
        subscriptionRejectedByServer = false
        rejectedOwnerAccountId = nil
    }

    var subscriptionStatus: String {
        guard isPro else { return "Free" }
        if isInGracePeriod { return "Grace Period" }
        if let exp = expirationDate, exp < Date() { return String(localized: "Expired") }
        if activeEntitlement?.willRenew == false { return String(localized: "Canceled") }
        return String(localized: "Active")
    }

    var continueButtonTitle: LocalizedStringKey {
        if isTrialEligible && trialDays > 0 {
            return "Start Free Trial"
        }
        return "Continue"
    }

    // MARK: - Private

    private var delegateProxy: PurchasesDelegateProxy?

    // MARK: - Configuration

    /// Sets up the delegate for customer info updates.
    /// Call after `Purchases.configure()` has been called in App.init.
    func configure() {
        guard RevenueCatConfig.isConfigured else {
            NSLog("[RevenueCatService] REVENUECAT_IOS_API_KEY not set in Info.plist — purchases disabled.")
            return
        }

        let proxy = PurchasesDelegateProxy { [weak self] info in
            Task { @MainActor [weak self] in
                self?.customerInfo = info
            }
        }
        self.delegateProxy = proxy
        Purchases.shared.delegate = proxy

        isConfigured = true
    }

    /// Link RevenueCat customer to your Supabase account ID.
    /// Call after user authentication. Clears any prior rejection state.
    func logIn(accountId: String) async {
        guard isConfigured else { return }
        // Clear stale rejection from a previous account session
        clearSubscriptionRejection()
        guard Purchases.shared.appUserID != accountId else { return }
        do {
            let (info, _) = try await Purchases.shared.logIn(accountId)
            self.customerInfo = info
        } catch {
            NSLog("[RevenueCatService] logIn failed: %@", error.localizedDescription)
        }
    }

    // MARK: - Fetch

    func fetchOfferings() async {
        guard isConfigured else { return }

        isLoading = true
        error = nil

        do {
            async let offeringsResult = Purchases.shared.offerings()
            async let infoResult = Purchases.shared.customerInfo()

            let (offs, info) = try await (offeringsResult, infoResult)
            self.customerInfo = info

            if let current = offs.current {
                self.packages = current.availablePackages.compactMap {
                    SubscriptionPackage.from(rcPackage: $0)
                }
            }

            await checkTrialEligibility()
        } catch {
            self.error = "Failed to load subscription options."
            NSLog("[RevenueCatService] fetchOfferings error: %@", error.localizedDescription)
        }

        isLoading = false
    }

    func refreshCustomerInfo() async {
        guard isConfigured else { return }
        do {
            self.customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            // Silent refresh failure
        }
    }

    // MARK: - Purchase

    func purchase(package: SubscriptionPackage) async -> PurchaseResult {
        do {
            let result = try await Purchases.shared.purchase(package: package.rcPackage)

            if result.userCancelled {
                return PurchaseResult(success: false, error: nil, tier: currentTier)
            }

            self.customerInfo = result.customerInfo
            let tier = determineTier(from: result.customerInfo)

            return PurchaseResult(
                success: tier != .free,
                error: tier == .free ? "Purchase did not activate subscription." : nil,
                tier: tier
            )
        } catch let error as RevenueCat.ErrorCode {
            return handlePurchaseError(error)
        } catch {
            return PurchaseResult(
                success: false,
                error: error.localizedDescription,
                tier: currentTier
            )
        }
    }

    // MARK: - Restore

    /// Restores purchases from the App Store via RevenueCat.
    /// Does NOT verify ownership — call `verifyAndSyncRestore` for the full flow.
    func restorePurchases() async -> RestoreResult {
        do {
            let info = try await Purchases.shared.restorePurchases()
            self.customerInfo = info
            let tier = determineTier(from: info)
            return RestoreResult(success: true, restored: tier != .free, error: nil)
        } catch {
            return RestoreResult(
                success: false,
                restored: false,
                error: "Restore failed: \(error.localizedDescription)"
            )
        }
    }

    /// Full restore flow: restore from App Store, then verify ownership via Supabase.
    /// Returns `.ownershipConflict` if the subscription belongs to a different account.
    func verifyAndSyncRestore(
        accountId: String,
        syncService: SubscriptionSyncService
    ) async -> RestoreResult {
        // Step 1: Restore from App Store
        let rcResult = await restorePurchases()

        guard rcResult.success, rcResult.restored else {
            // RC restore failed — if we already know from startup sync who owns the sub,
            // return ownership conflict so the UI shows the proper switch-account popup.
            if subscriptionRejectedByServer, let owner = rejectedOwnerAccountId {
                return RestoreResult(
                    success: false,
                    restored: false,
                    error: nil,
                    ownershipConflict: true,
                    ownerAccountId: owner
                )
            }
            return rcResult
        }

        // Step 2: Build transaction ID (matching SubscriptionSyncService format)
        guard let info = customerInfo else {
            return rcResult
        }

        let tier = determineTier(from: info)
        guard tier != .free else {
            return RestoreResult(success: true, restored: false, error: nil)
        }

        let entitlementId = tier == .premium ? RCEntitlements.premium : RCEntitlements.pro
        guard let entitlement = info.entitlements.active[entitlementId] else {
            return rcResult
        }

        let productId = entitlement.productIdentifier
        let dateString: String
        if let originalDate = entitlement.originalPurchaseDate {
            dateString = ISO8601DateFormatter().string(from: originalDate)
        } else {
            dateString = "unknown"
        }
        let originalTransactionId = "\(productId)_\(dateString)"

        // Step 3: Verify ownership
        let verification = await syncService.verifyRestore(
            accountId: accountId,
            originalTransactionId: originalTransactionId
        )

        switch verification {
        case .rejected(let owner):
            markSubscriptionRejected(owner: owner)
            return RestoreResult(
                success: false,
                restored: false,
                error: nil,
                ownershipConflict: true,
                ownerAccountId: owner
            )
        case .error(let msg):
            NSLog("[RevenueCatService] Restore verification error: %@", msg)
            // Fall through to sync — don't block on verification errors
        case .allowed:
            break
        }

        // Step 4: Sync to Supabase (claim_subscription will also enforce ownership)
        let syncResult = await syncService.sync(
            accountId: accountId,
            customerInfo: info,
            tier: tier
        )

        switch syncResult {
        case .rejected(let owner):
            markSubscriptionRejected(owner: owner)
            return RestoreResult(
                success: false,
                restored: false,
                error: nil,
                ownershipConflict: true,
                ownerAccountId: owner
            )
        case .success, .skipped:
            clearSubscriptionRejection()
            return RestoreResult(success: true, restored: true, error: nil)
        case .error(let msg):
            return RestoreResult(success: true, restored: true, error: msg)
        }
    }

    // MARK: - Private Helpers

    private func determineTier(from info: CustomerInfo?) -> SubscriptionTier {
        guard let entitlements = info?.entitlements.active else { return .free }
        if entitlements[RCEntitlements.premium]?.isActive == true { return .premium }
        if entitlements[RCEntitlements.pro]?.isActive == true { return .pro }
        return .free
    }

    private func checkTrialEligibility() async {
        do {
            let eligibility = try await Purchases.shared.checkTrialOrIntroDiscountEligibility(
                productIdentifiers: [RCProducts.yearly]
            )
            if let yearlyEligibility = eligibility[RCProducts.yearly] {
                self.isTrialEligible = yearlyEligibility.status == .eligible
            }
            if let yearly = yearlyPackage {
                self.trialDays = yearly.trialDays
            }
        } catch {
            self.isTrialEligible = false
        }
    }

    private func handlePurchaseError(_ error: RevenueCat.ErrorCode) -> PurchaseResult {
        switch error {
        case .purchaseCancelledError:
            return PurchaseResult(success: false, error: nil, tier: currentTier)
        case .productAlreadyPurchasedError:
            Task { await refreshCustomerInfo() }
            return PurchaseResult(success: true, error: nil, tier: currentTier)
        case .storeProblemError:
            return PurchaseResult(success: false, error: "There was a problem with the App Store. Please try again later.", tier: currentTier)
        case .networkError:
            return PurchaseResult(success: false, error: "Network error. Check your connection and try again.", tier: currentTier)
        case .purchaseNotAllowedError:
            return PurchaseResult(success: false, error: "Purchases are not allowed on this device.", tier: currentTier)
        case .paymentPendingError:
            return PurchaseResult(success: false, error: "Payment is pending approval.", tier: currentTier)
        default:
            return PurchaseResult(success: false, error: "Purchase failed. Please try again.", tier: currentTier)
        }
    }
}

// MARK: - Delegate Proxy

private final class PurchasesDelegateProxy: NSObject, PurchasesDelegate, @unchecked Sendable {
    private let handler: (CustomerInfo) -> Void

    init(handler: @escaping (CustomerInfo) -> Void) {
        self.handler = handler
    }

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        handler(customerInfo)
    }
}
