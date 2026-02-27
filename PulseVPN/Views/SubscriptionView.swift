import SwiftUI
import RevenueCat

// MARK: - Subscription View

struct SubscriptionView: View {
    let accountManager: AccountManager
    let rcService: RevenueCatService

    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreMessage: String?

    private var account: Account? { accountManager.account }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Hero area — image covering top ~50% with gradient fade
                heroSection

                // Content below hero
                VStack(spacing: Design.Spacing.lg) {
                    featuresCard

                    if rcService.isPro {
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
        .task {
            await rcService.refreshCustomerInfo()
        }
    }

    // MARK: - Hero Section (top ~50% of screen)

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            // Full-bleed dark hero image
            Image("SubscriptionHero")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
                .frame(height: 420)
                .clipped()

            // Gradient fading into the page background
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black.opacity(0.3), location: 0.25),
                    .init(color: .black.opacity(0.7), location: 0.55),
                    .init(color: Design.Colors.surfaceBackground, location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Plan info + app logo overlaid
            VStack(spacing: Design.Spacing.md) {
                // App logo in iOS squircle shape
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Design.Colors.accent, Design.Colors.accentDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                // Plan name
                Text(rcService.isPro ? "\(rcService.currentTier.displayName) Plan" : "Free Plan")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text(rcService.isPro ? "All features unlocked" : "Upgrade for premium servers")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                // Expiration / Renewal info
                if let expiry = rcService.expirationDate, rcService.isPro {
                    HStack(spacing: 4) {
                        Text(rcService.activeEntitlement?.willRenew == true ? "Renews" : "Expires")
                            .foregroundStyle(.white.opacity(0.6))
                        Text(expiry, style: .date)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .font(.system(.caption, design: .rounded))
                }

                // Grace period warning
                if rcService.isInGracePeriod {
                    Label("Update your payment method", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.horizontal, Design.Spacing.lg)
            .padding(.bottom, Design.Spacing.xl)
        }
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
                featureRow(icon: "globe", title: "Premium Servers", subtitle: "Access all global locations", included: rcService.isPro)
                Divider().padding(.leading, 40)
                featureRow(icon: "shield.checkered", title: "Ad Blocking", subtitle: "Block ads across all apps", included: rcService.isPro)
                Divider().padding(.leading, 40)
                featureRow(icon: "iphone.gen3", title: "Multiple Devices", subtitle: "Up to 5 simultaneous connections", included: rcService.isPro)
                Divider().padding(.leading, 40)
                featureRow(icon: "bolt.fill", title: "Priority Support", subtitle: "Faster response times", included: rcService.isPro)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.sm)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, subtitle: String, included: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(included ? .blue : Design.Colors.textTertiary)
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
        SecondaryCTAButton("Manage Subscription", icon: "arrow.up.right") {
            openSubscriptionManagement()
        }
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
        GlassEffectContainer {
            VStack(spacing: 0) {
                Button {
                    Task { await restorePurchases() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Design.Colors.textSecondary)
                            .frame(width: 24)

                        Text("Restore Purchases")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        if isRestoring {
                            ProgressView()
                        }
                    }
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(isRestoring)

                // Restore feedback
                if let message = restoreMessage {
                    Text(message)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
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
        #endif
    }

    private func restorePurchases() async {
        guard !isRestoring else { return }

        isRestoring = true
        restoreMessage = nil

        let result = await rcService.restorePurchases()

        isRestoring = false

        if result.restored {
            restoreMessage = "Subscription restored successfully!"
        } else if let error = result.error {
            restoreMessage = error
        } else {
            restoreMessage = "No active subscriptions found for this Apple ID."
        }

        // Clear message after delay
        Task {
            try? await Task.sleep(for: .seconds(4))
            restoreMessage = nil
        }
    }
}

// MARK: - Previews

#Preview("Subscription") {
    NavigationStack {
        SubscriptionView(accountManager: AccountManager(), rcService: RevenueCatService())
    }
}
