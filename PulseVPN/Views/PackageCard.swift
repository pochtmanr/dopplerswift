import SwiftUI

// MARK: - Package Card

struct PackageCard: View {
    let package: SubscriptionPackage
    let isSelected: Bool
    var badgeText: String? = nil
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Radio indicator
                Circle()
                    .strokeBorder(isSelected ? Design.Colors.accent : .gray.opacity(0.4), lineWidth: 2)
                    .background(
                        Circle()
                            .fill(isSelected ? Design.Colors.accent : .clear)
                            .padding(4)
                    )
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(package.period.displayName)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(.primary)

                        if let badge = badgeText {
                            Text(badge)
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Design.Colors.accent, in: Capsule())
                        }
                    }

                    Text(package.billingDescription)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(package.pricePerMonthString + "/mo")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
            }
            .padding(Design.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .fill(isSelected ? Design.Colors.accent.opacity(0.08) : Design.Colors.surfaceCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                    .strokeBorder(isSelected ? Design.Colors.accent : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
