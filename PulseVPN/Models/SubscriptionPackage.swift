import Foundation
import RevenueCat
import SwiftUI

// MARK: - Constants

enum RCEntitlements {
    static let pro = "VPN Simnetiq Pro"
    static let premium = "premium"
}

enum RCProducts {
    static let monthly = "vpn_premium_monthly"
    static let sixMonth = "vpn_premium_6m"
    static let yearly = "vpn_premium_yearly"
}

// MARK: - Subscription Tier

enum SubscriptionTier: String, Comparable, Sendable {
    case free
    case pro
    case premium

    private var rank: Int {
        switch self {
        case .free: return 0
        case .pro: return 1
        case .premium: return 2
        }
    }

    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        lhs.rank < rhs.rank
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .premium: return "Premium"
        }
    }
}

// MARK: - Package Period

enum PackagePeriod: String, CaseIterable, Sendable {
    case monthly = "MONTHLY"
    case sixMonth = "SIX_MONTH"
    case annual = "ANNUAL"

    var displayName: LocalizedStringKey {
        switch self {
        case .monthly: return "Monthly"
        case .sixMonth: return "6 Months"
        case .annual: return "Yearly"
        }
    }

    var displayNameRaw: String {
        switch self {
        case .monthly: return "monthly"
        case .sixMonth: return "6 months"
        case .annual: return "yearly"
        }
    }

    var monthCount: Int {
        switch self {
        case .monthly: return 1
        case .sixMonth: return 6
        case .annual: return 12
        }
    }
}

// MARK: - Subscription Package

struct SubscriptionPackage: Identifiable, Sendable {
    let id: String
    let period: PackagePeriod
    let price: Decimal
    let priceString: String
    let pricePerMonth: Decimal
    let pricePerMonthString: String
    let currencyCode: String
    let rcPackage: RevenueCat.Package
    let hasFreeTrial: Bool
    let trialDays: Int

    var billingDescription: String {
        "\(priceString) / \(period.displayNameRaw)"
    }

    static func from(rcPackage: RevenueCat.Package) -> SubscriptionPackage? {
        let period: PackagePeriod
        switch rcPackage.packageType {
        case .monthly:
            period = .monthly
        case .sixMonth:
            period = .sixMonth
        case .annual:
            period = .annual
        default:
            return nil
        }

        let product = rcPackage.storeProduct
        let price = product.price as Decimal
        let months = Decimal(period.monthCount)
        let perMonth = price / months

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = product.currencyCode ?? "USD"
        formatter.locale = product.priceFormatter?.locale ?? .current

        let perMonthString = formatter.string(from: perMonth as NSDecimalNumber) ?? ""

        let introPrice = product.introductoryDiscount
        let hasFreeTrial = introPrice?.paymentMode == .freeTrial
        let trialDays: Int
        if hasFreeTrial, let intro = introPrice {
            trialDays = intro.subscriptionPeriod.value * {
                switch intro.subscriptionPeriod.unit {
                case .day: return 1
                case .week: return 7
                case .month: return 30
                case .year: return 365
                @unknown default: return 0
                }
            }()
        } else {
            trialDays = 0
        }

        return SubscriptionPackage(
            id: rcPackage.identifier,
            period: period,
            price: price,
            priceString: product.localizedPriceString,
            pricePerMonth: perMonth,
            pricePerMonthString: perMonthString,
            currencyCode: product.currencyCode ?? "USD",
            rcPackage: rcPackage,
            hasFreeTrial: hasFreeTrial,
            trialDays: trialDays
        )
    }
}

// MARK: - Product ID Helpers

extension String {
    /// Derives a human-readable period name from a RevenueCat product identifier.
    var planPeriodName: LocalizedStringKey? {
        let lower = lowercased()
        if lower.contains("yearly") || lower.contains("annual") { return "Yearly" }
        if lower.contains("6m") || lower.contains("sixmonth") || lower.contains("six_month") { return "6 Months" }
        if lower.contains("monthly") { return "Monthly" }
        if lower.contains("weekly") { return "Weekly" }
        return nil
    }
}

// MARK: - Purchase / Restore Results

struct PurchaseResult: Sendable {
    let success: Bool
    let error: String?
    let tier: SubscriptionTier
}

struct RestoreResult: Sendable {
    let success: Bool
    let restored: Bool
    let error: String?
    var ownershipConflict: Bool = false
    var ownerAccountId: String?
}
