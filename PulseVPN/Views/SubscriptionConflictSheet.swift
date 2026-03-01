import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A polished sheet shown when the current account doesn't own the Apple ID subscription.
/// Displays the owner account ID (copyable) with a CTA to switch accounts.
struct SubscriptionConflictSheet: View {
    let ownerAccountId: String
    let onSwitchAccount: (String) -> Void
    let onDismiss: () -> Void
    let onContactSupport: () -> Void

    @State private var copied = false

    private var hasKnownOwner: Bool {
        ownerAccountId != "unknown" && !ownerAccountId.isEmpty
    }

    var body: some View {
        VStack(spacing: Design.Spacing.lg) {
            // Icon
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.15))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.2.slash.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            .padding(.top, Design.Spacing.lg)

            // Title
            Text("Subscription Belongs to Another Account")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)

            // Subtitle
            Text(hasKnownOwner
                 ? "This Apple ID's subscription is linked to a different Doppler VPN account. To use your Pro features, switch to the original account."
                 : "This Apple ID's subscription is linked to a different Doppler VPN account. Contact support to resolve this.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Design.Spacing.sm)

            if hasKnownOwner {
                // Account ID card (copyable)
                VStack(spacing: Design.Spacing.sm) {
                    Text("Original Account")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Button {
                        copyToClipboard(ownerAccountId)
                        withAnimation(.spring(response: 0.3)) {
                            copied = true
                        }
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { copied = false }
                        }
                    } label: {
                        HStack(spacing: Design.Spacing.sm) {
                            Text(ownerAccountId)
                                .font(.system(.body, design: .monospaced, weight: .semibold))
                                .foregroundStyle(Design.Colors.textPrimary)

                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(copied ? .green : Design.Colors.teal)
                        }
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: Design.CornerRadius.md))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                                .strokeBorder(
                                    copied ? .green.opacity(0.5) : Design.Colors.teal.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy account ID")

                    if copied {
                        Text("Copied!")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.green)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                // Primary CTA: Switch to owner account
                PrimaryCTAButton(title: "Switch to Original Account") {
                    onSwitchAccount(ownerAccountId)
                }
                .padding(.horizontal, Design.Spacing.sm)
            }

            // Secondary actions
            HStack(spacing: Design.Spacing.lg) {
                Button("Stay on Free") {
                    onDismiss()
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)

                Text("|")
                    .foregroundStyle(.quaternary)

                Button("Contact Support") {
                    onContactSupport()
                }
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.teal)
            }

            Spacer().frame(height: Design.Spacing.sm)
        }
        .padding(.horizontal, Design.Spacing.lg)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
