import SwiftUI
import RevenueCat

// MARK: - Paywall View

struct PaywallView: View {
    let rcService: RevenueCatService
    @Binding var isPresented: Bool

    @State private var selectedPackage: SubscriptionPackage?
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var purchaseError: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    // Logo + title
                    VStack(spacing: Design.Spacing.sm) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 56, height: 56)
                            .background(
                                LinearGradient(
                                    colors: [Design.Colors.accent, Design.Colors.accentDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .shadow(color: Design.Colors.accent.opacity(0.3), radius: 8, y: 4)

                        Text("Pulse Route Pro")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Unlock all features")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, Design.Spacing.xl)

                    // Feature list (Apple-required vertical format)
                    featureList

                    // Trial banner
                    if rcService.isTrialEligible && rcService.trialDays > 0 {
                        Text("\(rcService.trialDays)-day free trial, then auto-renews")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.vertical, Design.Spacing.sm)
                            .background(Design.Colors.accent.opacity(0.3), in: Capsule())
                    }

                    // Package cards or loading
                    if rcService.isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, Design.Spacing.xl)
                    } else {
                        packageCards
                    }

                    // Error
                    if let error = purchaseError {
                        Text(error)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal)
            }
            .scrollBounceBehavior(.basedOnSize)

            // Fixed bottom: CTA + legal + disclosure
            VStack(spacing: Design.Spacing.sm) {
                continueButton

                legalRow

                Text(disclosureText)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Design.Spacing.lg)
            }
            .padding(.horizontal)
            .padding(.top, Design.Spacing.md)
            .padding(.bottom, Design.Spacing.lg)
        }
        .background {
            GeometryReader { geo in
                Image("SubscriptionHero")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black.opacity(0.4), location: 0.25),
                                .init(color: .black.opacity(0.8), location: 0.5),
                                .init(color: .black, location: 0.7)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .task {
            if rcService.packages.isEmpty {
                await rcService.fetchOfferings()
            }
            if selectedPackage == nil {
                selectedPackage = rcService.yearlyPackage
            }
        }
    }

    // MARK: - Feature List

    @ViewBuilder
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow("shield.fill", "Premium Servers", "Access fast, low-latency servers worldwide")
            featureRow("arrow.triangle.branch", "Smart Route", "Direct routing for domestic websites")
            featureRow("map.fill", "Lite Trace", "Map view with server route tracking")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.xl)
    }

    @ViewBuilder
    private func featureRow(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Design.Colors.accent)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Package Cards

    @ViewBuilder
    private var packageCards: some View {
        VStack(spacing: 10) {
            if let yearly = rcService.yearlyPackage {
                PackageCard(
                    package: yearly,
                    isSelected: selectedPackage?.id == yearly.id,
                    badgeText: rcService.savingsPercentage > 0 ? "Save \(rcService.savingsPercentage)%" : nil
                ) {
                    selectedPackage = yearly
                }
            }
            if let sixMonth = rcService.sixMonthPackage {
                PackageCard(
                    package: sixMonth,
                    isSelected: selectedPackage?.id == sixMonth.id
                ) {
                    selectedPackage = sixMonth
                }
            }
            if let monthly = rcService.monthlyPackage {
                PackageCard(
                    package: monthly,
                    isSelected: selectedPackage?.id == monthly.id
                ) {
                    selectedPackage = monthly
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Continue Button

    @ViewBuilder
    private var continueButton: some View {
        PrimaryCTAButton(
            title: rcService.continueButtonTitle,
            isLoading: isPurchasing,
            isDisabled: selectedPackage == nil
        ) {
            Task { await purchaseSelected() }
        }
    }

    // MARK: - Legal Row

    @ViewBuilder
    private var legalRow: some View {
        HStack(spacing: Design.Spacing.md) {
            Button {
                Task { await restorePurchases() }
            } label: {
                if isRestoring {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.45))
                } else {
                    Text("Restore")
                }
            }
            .disabled(isRestoring)

            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 14)

            Link("Terms", destination: URL(string: "https://dopplervpn.com/terms")!)

            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 14)

            Link("Privacy", destination: URL(string: "https://dopplervpn.com/privacy")!)
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(.white.opacity(0.45))
    }

    // MARK: - Actions

    private func purchaseSelected() async {
        guard let package = selectedPackage else { return }
        guard !isPurchasing else { return }

        isPurchasing = true
        purchaseError = nil

        let result = await rcService.purchase(package: package)

        isPurchasing = false

        if result.success {
            isPresented = false
        } else if let error = result.error {
            purchaseError = error
        }
    }

    private func restorePurchases() async {
        guard !isRestoring else { return }

        isRestoring = true
        purchaseError = nil

        let result = await rcService.restorePurchases()

        isRestoring = false

        if result.restored {
            isPresented = false
        } else if !result.success {
            purchaseError = result.error
        } else {
            purchaseError = "No active subscriptions found for this Apple ID."
        }
    }

    // MARK: - Disclosure Text

    private var disclosureText: String {
        var text = "Payment will be charged to your Apple ID account at confirmation of purchase. "
        text += "Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. "
        text += "Your account will be charged for renewal within 24 hours prior to the end of the current period."
        if rcService.isTrialEligible && rcService.trialDays > 0 {
            text += " Free trial will convert to a paid subscription unless canceled before the trial period ends."
        }
        return text
    }
}
