import SwiftUI

// MARK: - Help & Support View

struct HelpSupportView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.lg) {
                // Quick Support
                quickSupportSection

                // Help Center
                helpCenterSection

                // FAQ
                faqSection

                // Response Time
                responseTimeCard
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.md)
        }
        .navigationTitle("Help & Support")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Quick Support

    @ViewBuilder
    private var quickSupportSection: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // Email
                Button {
                    openEmail()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Design.Colors.teal)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email Us")
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("support@simnetiq.store")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 40)

                // Telegram
                Button {
                    openTelegram()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Design.Colors.teal)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Telegram")
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("@DopplerSupportBot")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 14)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
    }

    // MARK: - Help Center

    @ViewBuilder
    private var helpCenterSection: some View {
        GlassEffectContainer {
            Button {
                openHelpCenter()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Design.Colors.teal)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Help Center")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(.primary)
                        Text("Full guides & troubleshooting")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
    }

    // MARK: - FAQ

    @ViewBuilder
    private var faqSection: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                ForEach(Array(FAQItem.allItems.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 40)
                    }
                    FAQRowView(item: item)
                }
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
    }

    // MARK: - Response Time Card

    @ViewBuilder
    private var responseTimeCard: some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: "clock.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Response Time")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text("We typically respond within 24 hours. Pro users get priority support.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Design.Spacing.md)
    }

    // MARK: - Actions

    private func openEmail() {
        #if os(iOS)
        if let url = URL(string: "mailto:support@simnetiq.store") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func openTelegram() {
        #if os(iOS)
        if let url = URL(string: "https://t.me/DopplerSupportBot") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    private func openHelpCenter() {
        #if os(iOS)
        if let url = URL(string: "https://www.dopplervpn.org/en/guide/ios") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - FAQ Item

private struct FAQItem: Identifiable {
    let id = UUID()
    let question: LocalizedStringResource
    let answer: LocalizedStringResource
    let icon: String

    static let allItems: [FAQItem] = [
        FAQItem(
            question: "How do I connect?",
            answer: "Tap the connect button on the home screen. Select a server from the server list first, then tap connect. The VPN will establish a secure tunnel automatically.",
            icon: "wifi"
        ),
        FAQItem(
            question: "Why is my connection slow?",
            answer: "Try switching to a server closer to your location. Server load can also affect speed — look for servers with lower usage. Pro users have access to premium high-speed servers.",
            icon: "speedometer"
        ),
        FAQItem(
            question: "What is Smart Route?",
            answer: "Smart Route lets domestic websites and services connect directly so they load faster and work correctly. Choose your home country, and Doppler VPN automatically routes local banking, government, streaming, and e-commerce traffic through a direct connection. You can also add custom domains.",
            icon: "arrow.triangle.branch"
        ),
        FAQItem(
            question: "How do I manage my subscription?",
            answer: "Go to Profile → Subscription to view your current plan. You can upgrade, restore purchases, or manage your subscription through the App Store.",
            icon: "creditcard"
        ),
        FAQItem(
            question: "Is my connection secure?",
            answer: "Yes. Doppler VPN uses advanced encryption protocols to protect your traffic. All data is fully encrypted end-to-end, ensuring your online activity remains private and secure.",
            icon: "lock.shield"
        ),
    ]
}

// MARK: - FAQ Row View

private struct FAQRowView: View {
    let item: FAQItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Design.Animation.springQuick) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(.systemGray))
                        .frame(width: 24)

                    Text(item.question)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(item.answer)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 36)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Previews

#Preview("Help & Support") {
    NavigationStack {
        HelpSupportView()
    }
}
