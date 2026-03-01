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
    @State private var showSuccess = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Main paywall content
            VStack(spacing: 0) {
                // Scrollable content
                ScrollView {
                    VStack(spacing: Design.Spacing.lg) {
                        // App icon + title
                        VStack(spacing: Design.Spacing.md) {
                            Image("AppLogo")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 80, height: 80)
                                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                                .shadow(color: .white.opacity(0.1), radius: 12)

                            VStack(spacing: Design.Spacing.xs) {
                                Text("Doppler VPN Pro")
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .foregroundStyle(.white)

                                Text("Unlock all features")
                                    .font(.system(.subheadline, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
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
                                .background(Design.Colors.teal.opacity(0.3), in: Capsule())
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

                    disclosureView
                }
                .padding(.horizontal)
                .padding(.top, Design.Spacing.md)
                .padding(.bottom, Design.Spacing.lg)
            }
            .opacity(showSuccess ? 0 : 1)

            // Success overlay
            if showSuccess {
                PurchaseSuccessView()
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
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
            featureRow("headset", "Priority Support", "Fast, dedicated customer support")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Design.Spacing.xl)
    }

    @ViewBuilder
    private func featureRow(_ icon: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

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

            Link("Terms", destination: URL(string: "https://www.dopplervpn.org/en/terms")!)

            Rectangle().fill(.white.opacity(0.3)).frame(width: 1, height: 14)

            Link("Privacy", destination: URL(string: "https://www.dopplervpn.org/en/privacy")!)
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
            showSuccessAndDismiss()
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
            showSuccessAndDismiss()
        } else if !result.success {
            purchaseError = result.error
        } else {
            purchaseError = String(localized: "No active subscriptions found for this Apple ID.")
        }
    }

    // MARK: - Success Transition

    private func showSuccessAndDismiss() {
        withAnimation(Design.Animation.springDefault) {
            showSuccess = true
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            isPresented = false
        }
    }

    // MARK: - Disclosure View

    @ViewBuilder
    private var disclosureView: some View {
        VStack(spacing: 2) {
            Text("Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period.")

            if rcService.isTrialEligible && rcService.trialDays > 0 {
                Text("Free trial will convert to a paid subscription unless canceled before the trial period ends.")
            }
        }
        .font(.system(size: 11, design: .rounded))
        .foregroundStyle(.white.opacity(0.3))
        .multilineTextAlignment(.center)
        .padding(.horizontal, Design.Spacing.lg)
    }
}

// MARK: - Purchase Success View

private struct PurchaseSuccessView: View {

    @State private var showCheckmark = false
    @State private var showRing = false
    @State private var showText = false
    @State private var ringScale: CGFloat = 0.6
    @State private var particles: [SuccessParticle] = []

    private let particleCount = 12

    var body: some View {
        VStack(spacing: Design.Spacing.xl) {
            Spacer()

            ZStack {
                // Glowing ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Design.Colors.teal,
                                Design.Colors.teal.opacity(0.6),
                                .white.opacity(0.3),
                                Design.Colors.teal.opacity(0.6),
                                Design.Colors.teal,
                            ],
                            center: .center
                        ),
                        lineWidth: 3
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(ringScale)
                    .opacity(showRing ? 1 : 0)
                    .blur(radius: showRing ? 0 : 4)

                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Design.Colors.teal.opacity(0.3),
                                Design.Colors.teal.opacity(0.05),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                    .opacity(showRing ? 1 : 0)

                // Checkmark icon
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(Design.Colors.teal)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(showCheckmark ? 1.0 : 0.3)
                    .opacity(showCheckmark ? 1 : 0)

                // Particles
                ForEach(particles) { particle in
                    Circle()
                        .fill(particle.color)
                        .frame(width: particle.size, height: particle.size)
                        .offset(particle.offset)
                        .opacity(particle.opacity)
                }
            }
            .frame(width: 160, height: 160)

            // Text content
            VStack(spacing: Design.Spacing.sm) {
                Text("Thank You!")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)

                Text("You're now a Pro member")
                    .font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                Text("Enjoy all premium features")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .multilineTextAlignment(.center)
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 16)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await animateEntrance()
        }
    }

    // MARK: - Animation Sequence

    private func animateEntrance() async {
        // Step 1: Ring appears
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            showRing = true
            ringScale = 1.0
        }

        try? await Task.sleep(for: .milliseconds(150))

        // Step 2: Checkmark scales in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
            showCheckmark = true
        }

        try? await Task.sleep(for: .milliseconds(200))

        // Step 3: Particles burst
        spawnParticles()

        try? await Task.sleep(for: .milliseconds(100))

        // Step 4: Text fades in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showText = true
        }

        // Step 5: Fade out particles
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.easeOut(duration: 0.6)) {
            for index in particles.indices {
                particles[index].opacity = 0
            }
        }
    }

    private func spawnParticles() {
        let colors: [Color] = [
            Design.Colors.teal,
            Design.Colors.teal.opacity(0.7),
            .white.opacity(0.8),
            Design.Colors.premium,
            Design.Colors.premium.opacity(0.6),
        ]

        for i in 0..<particleCount {
            let angle = (Double(i) / Double(particleCount)) * 2.0 * .pi
            let distance: CGFloat = CGFloat.random(in: 60...100)
            let particle = SuccessParticle(
                id: i,
                color: colors[i % colors.count],
                size: CGFloat.random(in: 4...8),
                offset: .zero,
                opacity: 1.0
            )
            particles.append(particle)

            let targetOffset = CGSize(
                width: CGFloat(cos(angle)) * distance,
                height: CGFloat(sin(angle)) * distance
            )

            withAnimation(.spring(response: 0.6, dampingFraction: 0.5).delay(Double(i) * 0.02)) {
                particles[i].offset = targetOffset
            }
        }
    }
}

// MARK: - Success Particle Model

private struct SuccessParticle: Identifiable {
    let id: Int
    let color: Color
    let size: CGFloat
    var offset: CGSize
    var opacity: Double
}
