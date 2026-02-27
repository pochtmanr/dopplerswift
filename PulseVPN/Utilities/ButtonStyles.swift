import SwiftUI

// MARK: - Scale Press Style (shared)

struct ScalePressStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Design.Animation.springQuick, value: configuration.isPressed)
    }
}

// MARK: - Primary CTA Button (fully rounded gradient)

struct PrimaryCTAButton: View {
    let title: String
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
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
        .disabled(isLoading || isDisabled)
        .buttonStyle(ScalePressStyle())
    }
}

// MARK: - Secondary CTA Button (bordered capsule)

struct SecondaryCTAButton: View {
    let title: String
    let icon: String?
    let action: () -> Void

    init(_ title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
                Spacer()
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .padding(Design.Spacing.md)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(ScalePressStyle())
        .tint(.accentColor)
    }
}
