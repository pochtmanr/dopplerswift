import SwiftUI

// MARK: - Welcome View

struct WelcomeView: View {
    let onContinue: () -> Void

    // MARK: - State

    @State private var currentPhraseIndex = 0
    @State private var timer: Timer?

    // MARK: - Constants

    private let phrases: [LocalizedStringKey] = [
        "to privacy.",
        "to be let alone.",
        "to digital safety.",
        "to be forgotten.",
        "to say no.",
        "to silence.",
        "to choose who sees them.",
        "to be respected.",
        "to digital freedom.",
        "to own their online experience.",
        "to privacy online.",
        "to be shielded.",
        "to peace of mind.",
        "to control their data.",
        "to own their data.",
        "to be protected.",
        "to encrypt."
    ]

    private let phraseInterval: TimeInterval = 3.0

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background image
            GeometryReader { geo in
                Image("WelcomeBackground")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            // Content overlay
            VStack(spacing: Design.Spacing.lg) {
                Spacer()
                    .frame(maxHeight: 120)

                // Logo
                Image("AppLogo")
                    .renderingMode(.original)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                // Animated text
                VStack(spacing: Design.Spacing.sm) {
                    Text("Everyone has a right")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(phrases[currentPhraseIndex])
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .id(currentPhraseIndex)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .top).combined(with: .opacity)
                            )
                        )
                }

                Spacer()

                // CTA + legal at the bottom
                VStack(spacing: Design.Spacing.md) {
                    getStartedButton
                    legalFooter
                }
                .padding(.bottom, Design.Spacing.xl)
            }
            .padding(.horizontal, Design.Spacing.xl)
        }
        .onAppear {
            startPhraseTimer()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
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
                .padding(.vertical, 16)
                .background(Design.Colors.teal, in: Capsule())
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Get Started")
        .accessibilityHint("Begin setting up your VPN account")
    }

    @ViewBuilder
    private var legalFooter: some View {
        Text("By continuing, you agree to our [Terms](https://www.dopplervpn.org/en/terms) and [Privacy](https://www.dopplervpn.org/en/privacy)")
            .font(.system(.caption, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .tint(.white.opacity(0.8))
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
