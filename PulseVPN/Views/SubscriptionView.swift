import SwiftUI
import RevenueCat
#if os(macOS)
import AppKit
#endif

// MARK: - Subscription View

struct SubscriptionView: View {
    let accountManager: AccountManager
    let rcService: RevenueCatService
    let syncService: SubscriptionSyncService

    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?
    @State private var conflictOwnerAccountId: String?

    private var account: Account? { accountManager.account }

    /// Unified tier: RC first, Supabase fallback (handles web/Stripe subs)
    private var effectiveTier: SubscriptionTier {
        rcService.effectiveTier(fallbackAccount: account)
    }

    private var isEffectivelyPro: Bool { effectiveTier >= .pro }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            // Hero image as full background behind everything
            heroBackground

            ScrollView {
                VStack(spacing: 0) {
                    // Plan info at the top (over the image)
                    planInfoSection
                        .padding(.top, Design.Spacing.xl)

                    // Content cards that overlap onto the hero
                    VStack(spacing: Design.Spacing.lg) {
                        // Show owner account banner when subscription was rejected
                        if rcService.subscriptionRejectedByServer,
                           let ownerId = rcService.rejectedOwnerAccountId {
                            rejectedSubscriptionBanner(ownerId: ownerId)
                        }

                        featuresCard

                        if isEffectivelyPro {
                            manageSection
                        } else {
                            upgradeButton
                        }

                        secondaryActions

                        legalFooter
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.top, Design.Spacing.lg)
                    .padding(.bottom, Design.Spacing.md)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Subscription")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showPaywall) {
            PaywallView(rcService: rcService, isPresented: $showPaywall)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
        }
        .sheet(item: $conflictOwnerAccountId) { ownerId in
            SubscriptionConflictSheet(
                ownerAccountId: ownerId,
                onSwitchAccount: { switchToOwnerAccount($0) },
                onDismiss: { conflictOwnerAccountId = nil },
                onContactSupport: {
                    conflictOwnerAccountId = nil
                    openSupportEmail()
                }
            )
            .presentationBackground(.ultraThinMaterial)
        }
        .task {
            await rcService.refreshCustomerInfo()
        }
    }

    // MARK: - Hero Background (pinned behind scroll)

    @ViewBuilder
    private var heroBackground: some View {
        GeometryReader { geo in
            Image("SubscriptionHero")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: geo.size.width, height: geo.size.height * 0.55)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black.opacity(0.2), location: 0.3),
                            .init(color: .black.opacity(0.6), location: 0.6),
                            .init(color: Design.Colors.surfaceBackground, location: 1.0),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .ignoresSafeArea()
    }

    // MARK: - Plan Info (over the hero image)

    @ViewBuilder
    private var planInfoSection: some View {
        VStack(spacing: Design.Spacing.sm) {
            // App logo
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .foregroundStyle(.white)
                .background(
                    LinearGradient(
                        colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)

            // Plan name with period
            if isEffectivelyPro, let entitlement = rcService.activeEntitlement {
                Text("\(effectiveTier.displayName) Plan")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                // Status badge
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusBadgeColor)
                        .frame(width: 8, height: 8)
                    Text(rcService.subscriptionStatus)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    if let periodName = entitlement.productIdentifier.planPeriodName {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.4))
                        Text(periodName)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                // Expiration / Renewal info
                if let expiry = rcService.expirationDate {
                    HStack(spacing: 4) {
                        if entitlement.willRenew {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Auto-renews")
                        } else {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Expires")
                        }
                        Text(expiry, style: .date)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                }
            } else if isEffectivelyPro {
                // Pro via Supabase (web/Stripe subscription), no RC entitlement
                Text("\(effectiveTier.displayName) Plan")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("All features unlocked")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Free Plan")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("Upgrade for premium servers")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // Grace period warning with action
            if rcService.isInGracePeriod {
                Button {
                    openSubscriptionManagement()
                } label: {
                    Label("Update your payment method", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, Design.Spacing.sm)
                        .background(.orange.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(.horizontal, Design.Spacing.lg)
    }

    private var statusBadgeColor: Color {
        switch rcService.subscriptionStatus {
        case "Active": return .green
        case "Grace Period": return .orange
        case "Canceled": return .yellow
        case "Expired": return .red
        default: return .secondary
        }
    }

    // MARK: - Features Card

    @ViewBuilder
    private var featuresCard: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                featureRow(icon: "globe", title: "Premium Servers", subtitle: "Access all global locations", included: isEffectivelyPro)
                Divider().padding(.leading, 40)
                featureRow(icon: "arrow.triangle.branch", title: "Smart Routing", subtitle: "Intelligent traffic routing by country", included: isEffectivelyPro)
                Divider().padding(.leading, 40)
                featureRow(icon: "iphone.gen3", title: "Multiple Devices", subtitle: "Up to 10 per account", included: isEffectivelyPro)
                Divider().padding(.leading, 40)
                featureRow(icon: "bolt.fill", title: "Priority Support", subtitle: "Faster response times", included: isEffectivelyPro)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey, included: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(included ? Design.Colors.teal : Design.Colors.textTertiary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .medium))
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: included ? "checkmark.circle.fill" : "lock.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(included ? .green : Design.Colors.textTertiary)
        }
        .padding(.vertical, 12)
    }

    // MARK: - Manage Section (Pro users)

    @ViewBuilder
    private var manageSection: some View {
        VStack(spacing: Design.Spacing.sm) {
            SecondaryCTAButton("Manage Subscription", icon: "arrow.up.right") {
                openSubscriptionManagement()
            }

            if rcService.activeEntitlement?.willRenew == false {
                Text("Your subscription will not renew. You can resubscribe from the App Store.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Rejected Subscription Banner

    @ViewBuilder
    private func rejectedSubscriptionBanner(ownerId: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Subscription on Another Account")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text("Your Apple ID subscription is linked to:")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ownerId)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(Design.Colors.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(Design.Colors.teal.opacity(0.08), in: .rect(cornerRadius: Design.CornerRadius.md))

            Button {
                switchToOwnerAccount(ownerId)
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Switch to \(ownerId)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
            }
            .buttonStyle(ScalePressStyle())
        }
        .padding(Design.Spacing.md)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: Design.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Upgrade Button (Free users)

    @ViewBuilder
    private var upgradeButton: some View {
        PrimaryCTAButton(title: "Upgrade to Pro") {
            showPaywall = true
        }
    }

    // MARK: - Secondary Actions

    @ViewBuilder
    private var secondaryActions: some View {
        Button {
            Task { await restorePurchases() }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                if isRestoring {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }

                Text(isRestoring ? "Restoring..." : "Restore Purchases")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .foregroundStyle(Design.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.md)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(ScalePressStyle())
        .disabled(isRestoring)

        // Restore feedback
        if let message = restoreMessage {
            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Legal Footer

    @ViewBuilder
    private var legalFooter: some View {
        Text("Payment will be charged to your Apple ID account. Subscription automatically renews unless canceled at least 24 hours before the end of the current period.")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Design.Spacing.md)
    }

    // MARK: - Actions

    private func openSubscriptionManagement() {
        #if os(iOS)
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        // StoreKit 2's showManageSubscriptions is unreliable on macOS.
        // Open App Store subscriptions pane directly via deep link.
        if let url = URL(string: "macappstores://apps.apple.com/account/subscriptions") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func switchToOwnerAccount(_ ownerId: String) {
        // Set prefill so AccountSetupView auto-fills the login field
        accountManager.prefillAccountId = ownerId
        // Switch account (keeps onboarding complete, goes to login screen)
        accountManager.switchAccount()
    }

    private func openSupportEmail() {
        let currentAccountId = account?.accountId ?? "unknown"
        let ownerAccountId = conflictOwnerAccountId ?? "unknown"
        let subject = "Subscription Transfer Request"
        let body = """
        Hi Doppler VPN Support,

        I need help with a subscription issue.

        My current account ID: \(currentAccountId)
        Subscription owner account ID: \(ownerAccountId)

        Please help me resolve this subscription conflict.

        Thank you.
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:support@simnetiq.store?subject=\(encodedSubject)&body=\(encodedBody)") {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func restorePurchases() async {
        guard !isRestoring else { return }
        guard let accountId = account?.accountId else { return }

        isRestoring = true
        restoreMessage = nil

        let result = await rcService.verifyAndSyncRestore(
            accountId: accountId,
            syncService: syncService
        )

        isRestoring = false

        // 1. Restore succeeded and user got Pro — done
        if result.restored && !result.ownershipConflict {
            restoreMessage = String(localized: "Subscription restored successfully!")
            Task {
                try? await Task.sleep(for: .seconds(4))
                restoreMessage = nil
            }
            return
        }

        // 2. Every other case: show the conflict popup
        // Try to find the owner account ID from any source available
        var ownerId = result.ownerAccountId ?? rcService.rejectedOwnerAccountId
        if ownerId == nil {
            ownerId = await resolveOwnerFromSupabase(accountId: accountId)
        }

        let finalOwner = ownerId ?? "unknown"
        NSLog("[SubscriptionView] Showing conflict popup, owner: %@", finalOwner)
        conflictOwnerAccountId = finalOwner
    }

    /// Queries Supabase verify_restore to find who owns the subscription.
    /// Returns the owner account ID, or nil if we can't determine it.
    private func resolveOwnerFromSupabase(accountId: String) async -> String? {
        do {
            let info = try await Purchases.shared.customerInfo()
            let entitlements = info.entitlements.active
            let entitlement = entitlements[RCEntitlements.premium] ?? entitlements[RCEntitlements.pro]

            guard let entitlement else { return nil }

            let productId = entitlement.productIdentifier
            let dateString: String
            if let originalDate = entitlement.originalPurchaseDate {
                dateString = ISO8601DateFormatter().string(from: originalDate)
            } else {
                dateString = "unknown"
            }
            let txnId = "\(productId)_\(dateString)"

            let verification = await syncService.verifyRestore(
                accountId: accountId,
                originalTransactionId: txnId
            )

            if case .rejected(let owner) = verification {
                rcService.markSubscriptionRejected(owner: owner)
                return owner
            }
        } catch {
            NSLog("[SubscriptionView] resolveOwner failed: %@", error.localizedDescription)
        }
        return nil
    }
}

// MARK: - String + Identifiable (for .sheet(item:))

extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Previews

#Preview("Subscription") {
    NavigationStack {
        SubscriptionView(accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService())
    }
}
