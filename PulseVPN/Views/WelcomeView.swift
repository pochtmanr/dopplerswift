import SwiftUI

// MARK: - Welcome View

struct WelcomeView: View {
    let onContinue: () -> Void

    // MARK: - State

    @State private var currentPhraseIndex = 0
    @State private var timer: Timer?
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0
    @State private var contentOpacity: Double = 0

    // MARK: - Constants

    private let phrases = [
        "to privacy.",
        "to be let alone.",
        "to digital safety.",
        "to be forgotten.",
        "to say no.",
        "to silence.",
        "to be unseen.",
        "to be respected.",
        "to digital sovereignty.",
        "to hold their own keys.",
        "to anonymity.",
        "to be shielded.",
        "to peace of mind.",
        "to keep secrets.",
        "to own their data.",
        "to be protected.",
        "to encrypt."
    ]

    private let phraseInterval: TimeInterval = 3.0

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundImage

            VStack(spacing: 0) {
                Spacer()

                heroSection

                Spacer()

                bottomSection
            }
            .padding(.horizontal, Design.Spacing.lg)
        }
        .onAppear {
            startPhraseTimer()
            startEntranceAnimation()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundImage: some View {
        GeometryReader { geo in
            ZStack {
                Design.Colors.surfaceBackground
                    .ignoresSafeArea()

                Image("WelcomeBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.45)

                // Light gradient at top and bottom for text readability
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Design.Colors.surfaceBackground.opacity(0.7),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.3)

                    Spacer()

                    LinearGradient(
                        colors: [
                            Color.clear,
                            Design.Colors.surfaceBackground.opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geo.size.height * 0.35)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Hero Section

    @ViewBuilder
    private var heroSection: some View {
        VStack(spacing: Design.Spacing.lg) {
            appLogo
            titleGroup
        }
        .opacity(contentOpacity)
    }

    @ViewBuilder
    private var appLogo: some View {
        Image("AppLogo")
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100, height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scaleEffect(iconScale)
            .opacity(iconOpacity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var titleGroup: some View {
        VStack(spacing: Design.Spacing.sm) {
            Text("Everyone has a right")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)
                .multilineTextAlignment(.center)

            animatedPhrase
        }
    }

    @ViewBuilder
    private var animatedPhrase: some View {
        Text(phrases[currentPhraseIndex])
            .font(.system(.title, design: .rounded, weight: .bold))
            .foregroundStyle(Design.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .id(currentPhraseIndex)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                )
            )
            .accessibilityLabel("Everyone has a right \(phrases[currentPhraseIndex])")
    }

    // MARK: - Bottom Section

    @ViewBuilder
    private var bottomSection: some View {
        VStack(spacing: Design.Spacing.md) {
            getStartedButton
            legalFooter
        }
        .padding(.bottom, Design.Spacing.xl)
        .opacity(contentOpacity)
    }

    @ViewBuilder
    private var getStartedButton: some View {
        Button {
            onContinue()
        } label: {
            Text("Get Started")
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Design.Colors.accent, Design.Colors.accentDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Design.Colors.accent.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Get Started")
        .accessibilityHint("Begin setting up your VPN account")
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .medium), trigger: currentPhraseIndex)
        #endif
    }

    @ViewBuilder
    private var legalFooter: some View {
        HStack(spacing: Design.Spacing.xs) {
            Text("By continuing, you agree to our")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Design.Colors.textTertiary)

            Link("Terms", destination: URL(string: "https://pulseroute.com/terms")!)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.accent)

            Text("and")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Design.Colors.textTertiary)

            Link("Privacy", destination: URL(string: "https://pulseroute.com/privacy")!)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.accent)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Design.Spacing.md)
    }

    // MARK: - Animation

    private func startPhraseTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: phraseInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentPhraseIndex = (currentPhraseIndex + 1) % phrases.count
            }
        }
    }

    private func startEntranceAnimation() {
        withAnimation(Design.Animation.springDefault.delay(0.1)) {
            iconScale = 1.0
            iconOpacity = 1.0
        }
        withAnimation(Design.Animation.springDefault.delay(0.3)) {
            contentOpacity = 1.0
        }
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(Design.Animation.springQuick, value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Welcome") {
    WelcomeView {
        // no-op
    }
}

#Preview("Welcome Dark") {
    WelcomeView {
        // no-op
    }
    .preferredColorScheme(.dark)
}
