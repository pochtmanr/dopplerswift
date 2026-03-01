import SwiftUI

// MARK: - Config Input View

struct ConfigInputView: View {
    let onAddServer: (VLessConfig) -> Void
    let onLoadSubscription: ([VLessConfig]) -> Void

    @State private var inputText = ""
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var pastedFromClipboard = false
    @Environment(\.dismiss) private var dismiss

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedInput.isEmpty
    }

    private var inputType: InputType {
        if trimmedInput.lowercased().hasPrefix("vless://") {
            return .vless
        } else if trimmedInput.lowercased().hasPrefix("https://") {
            return .subscription
        }
        return .unknown
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Design.Spacing.lg) {
                headerSection
                inputCard
                helpSection
            }
            .padding(Design.Spacing.lg)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Header Section

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: Design.Spacing.sm) {
            Image(systemName: "plus")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(Design.Colors.teal)

            Text("Add a Server")
                .font(.system(.title3, design: .rounded, weight: .bold))

            Text("Paste a server URI or subscription URL")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, Design.Spacing.sm)
    }

    // MARK: - Paste from Clipboard

    @ViewBuilder
    private var pasteFromClipboardButton: some View {
        #if os(iOS)
        Button {
            guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
            withAnimation(Design.Animation.springQuick) {
                inputText = text
                pastedFromClipboard = true
                errorMessage = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { pastedFromClipboard = false }
            }
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: pastedFromClipboard ? "checkmark" : "doc.on.clipboard")
                    .contentTransition(.symbolEffect(.replace))
                Text(pastedFromClipboard ? "Pasted" : "Paste from Clipboard")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(pastedFromClipboard ? .white : Design.Colors.textPrimary)
            .background(
                pastedFromClipboard ? AnyShapeStyle(.green) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
        }
        .buttonStyle(AddServerButtonStyle())
        #endif
    }

    // MARK: - Input Card

    @ViewBuilder
    private var inputCard: some View {
        GlassEffectContainer {
            VStack(spacing: Design.Spacing.md) {
                // Type indicator
                HStack(spacing: 6) {
                    inputTypeIcon
                    Text(inputTypeLabel)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !trimmedInput.isEmpty {
                        Button {
                            withAnimation(Design.Animation.springQuick) {
                                inputText = ""
                                errorMessage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }

                // Text field
                TextField(
                    "Server link or subscription URL",
                    text: $inputText,
                    axis: .vertical
                )
                .lineLimit(3...8)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .padding(Design.Spacing.md)
                .background(Design.Colors.surfaceCard, in: .rect(cornerRadius: Design.CornerRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                        .strokeBorder(
                            errorMessage != nil ? Color.red.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )

                // Error
                if let errorMessage {
                    HStack(spacing: Design.Spacing.sm) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)

                        Text(errorMessage)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Add button
                Button(action: handleAdd) {
                    HStack(spacing: Design.Spacing.sm) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                                .controlSize(.small)
                        }

                        Text(isLoading ? "Loading..." : "Add Server")
                            .font(.system(.body, design: .rounded, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .opacity(isValid && !isLoading ? 1.0 : 0.5)
                }
                .disabled(!isValid || isLoading)
                .buttonStyle(AddServerButtonStyle())

                // Paste from clipboard
                pasteFromClipboardButton
            }
            .padding(Design.Spacing.lg)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.xl))
        }
    }

    // MARK: - Input Type Indicator

    @ViewBuilder
    private var inputTypeIcon: some View {
        switch inputType {
        case .vless:
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .subscription:
            Image(systemName: "link")
                .foregroundStyle(Design.Colors.teal)
                .font(.caption)
        case .unknown:
            Image(systemName: "text.cursor")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
    }

    private var inputTypeLabel: String {
        switch inputType {
        case .vless: return String(localized: "Server URI detected")
        case .subscription: return String(localized: "Subscription URL detected")
        case .unknown: return String(localized: "Enter URI or URL")
        }
    }

    // MARK: - Help Section

    @ViewBuilder
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.md) {
            helpRow(
                icon: "lock.shield",
                title: "Server URI",
                description: "Paste a server link to add a single server"
            )

            helpRow(
                icon: "arrow.triangle.2.circlepath",
                title: "Subscription URL",
                description: "Paste a subscription URL to import multiple servers"
            )
        }
        .padding(Design.Spacing.md)
    }

    @ViewBuilder
    private func helpRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Design.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Design.Colors.teal)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))

                Text(description)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func handleAdd() {
        errorMessage = nil

        if trimmedInput.lowercased().hasPrefix("vless://") {
            do {
                let config = try VLessParser.parse(trimmedInput)
                onAddServer(config)
                inputText = ""
            } catch {
                withAnimation(Design.Animation.springQuick) {
                    errorMessage = error.localizedDescription
                }
            }
        } else if trimmedInput.lowercased().hasPrefix("https://") {
            Task {
                isLoading = true
                defer { isLoading = false }

                do {
                    let configs = try await SubscriptionService.fetch(url: trimmedInput)
                    onLoadSubscription(configs)
                    inputText = ""
                } catch {
                    withAnimation(Design.Animation.springQuick) {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } else {
            withAnimation(Design.Animation.springQuick) {
                errorMessage = String(localized: "Enter a valid server URI or subscription URL.")
            }
        }
    }
}

// MARK: - Button Style

private struct AddServerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Input Type

private enum InputType {
    case vless
    case subscription
    case unknown
}

// MARK: - Previews

#Preview {
    NavigationStack {
        ConfigInputView(
            onAddServer: { _ in },
            onLoadSubscription: { _ in }
        )
        .navigationTitle("Add Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

#Preview("Dark Mode") {
    NavigationStack {
        ConfigInputView(
            onAddServer: { _ in },
            onLoadSubscription: { _ in }
        )
        .navigationTitle("Add Server")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    .preferredColorScheme(.dark)
}
