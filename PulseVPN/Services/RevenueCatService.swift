import Foundation
import RevenueCat
import Observation

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

    var subscriptionStatus: String {
        guard isPro else { return "Free" }
        if isInGracePeriod { return "Grace Period" }
        if let exp = expirationDate, exp < Date() { return "Expired" }
        if activeEntitlement?.willRenew == false { return "Canceled" }
        return "Active"
    }

    var continueButtonTitle: String {
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
    /// Call after user authentication.
    func logIn(accountId: String) async {
        guard isConfigured else { return }
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
