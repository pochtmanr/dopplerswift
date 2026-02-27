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
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.black, Color(red: 0.05, green: 0.1, blue: 0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    // Close button
                    HStack {
                        Spacer()
                        Button { isPresented = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(.horizontal)

                    // Header
                    VStack(spacing: Design.Spacing.sm) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .foregroundStyle(.white)
                            .background(
                                LinearGradient(
                                    colors: [Design.Colors.accent, Design.Colors.accentDark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .shadow(color: Design.Colors.accent.opacity(0.4), radius: 12, y: 4)

                        Text("Doppler VPN Pro")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, Design.Spacing.lg)

                    // Hero image
                    Image("SubscriptionHero")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 170)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: Design.CornerRadius.lg))
                        .padding(.horizontal)

                    // Feature list
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

                    // Continue button
                    continueButton

                    // Legal row
                    legalRow

                    // Disclosure
                    Text(disclosureText)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Design.Spacing.lg)
                        .padding(.bottom, Design.Spacing.xl)
                }
            }
        }
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
            paywallFeatureRow("Premium Servers")
            paywallFeatureRow("Ad Blocking")
            paywallFeatureRow("Multiple Devices")
            paywallFeatureRow("Content Filter")
            paywallFeatureRow("Priority Support")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.xl)
    }

    @ViewBuilder
    private func paywallFeatureRow(_ title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Design.Colors.accent)
                .font(.system(size: 18))

            Text(title)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white)
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
        Button {
            Task { await purchaseSelected() }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(rcService.continueButtonTitle)
                        .font(.system(.body, design: .rounded, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [Design.Colors.accent, Design.Colors.accentDark],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: .rect(cornerRadius: Design.CornerRadius.lg)
            )
            .foregroundStyle(.white)
        }
        .disabled(selectedPackage == nil || isPurchasing)
        .padding(.horizontal)
        .buttonStyle(PaywallScaleButtonStyle())
    }

    // MARK: - Legal Row

    @ViewBuilder
    private var legalRow: some View {
        HStack(spacing: Design.Spacing.md) {
            Button("Restore") {
                Task { await restorePurchases() }
            }
            .disabled(isRestoring)

            Divider().frame(height: 14)

            Link("Terms", destination: URL(string: "https://dopplervpn.com/terms")!)

            Divider().frame(height: 14)

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

// MARK: - Scale Button Style

private struct PaywallScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
