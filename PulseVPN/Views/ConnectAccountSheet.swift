import SwiftUI

// MARK: - Connect Account Sheet

struct ConnectAccountSheet: View {
    let accountManager: AccountManager

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMethod: ContactMethod?
    @State private var inputValue = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false

    private var isAlreadyLinked: Bool {
        accountManager.account?.hasLinkedContact == true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if isAlreadyLinked {
                        linkedView
                    } else {
                        unlinkededView
                    }
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.md)
            }
            .navigationTitle("Connect Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isAlreadyLinked ? "Done" : "Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Already Linked View

    @ViewBuilder
    private var linkedView: some View {
        // Linked contact display
        if let method = accountManager.account?.contactMethod,
           let value = accountManager.account?.contactValue,
           let contactMethod = ContactMethod(rawValue: method) {
            VStack(spacing: Design.Spacing.lg) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(Design.Colors.teal)

                Text("Account Protected")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                // Contact info card
                HStack(spacing: 12) {
                    Image(systemName: contactMethod.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Design.Colors.teal)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contactMethod.localizedLabel)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                    }

                    Spacer()
                }
                .padding(Design.Spacing.md)
                .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.md))
            }
            .padding(.horizontal, Design.Spacing.md)
            .padding(.vertical, Design.Spacing.lg)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
        }

        // Disclaimers
        disclaimer

        changeDisclaimer
    }

    // MARK: - Not Yet Linked View

    @ViewBuilder
    private var unlinkededView: some View {
        disclaimer

        oneTimeDisclaimer

        if let method = selectedMethod {
            inputSection(method: method)
        } else {
            methodPicker
        }
    }

    // MARK: - Privacy Disclaimer

    @ViewBuilder
    private var disclaimer: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Design.Colors.teal)

            Text("Your contact info is used only for account recovery. We will never send marketing messages.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.md))
    }

    // MARK: - One-Time Link Disclaimer

    @ViewBuilder
    private var oneTimeDisclaimer: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)

            Text("Only one contact method can be linked per account. To change it later, please contact customer support.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.md))
    }

    // MARK: - Change Contact Disclaimer (shown when already linked)

    @ViewBuilder
    private var changeDisclaimer: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.orange)

            Text("To change your linked contact, please reach out to customer support via Help & Support.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(Design.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.md))
    }

    // MARK: - Method Picker

    @ViewBuilder
    private var methodPicker: some View {
        VStack(spacing: 0) {
            ForEach(Array(ContactMethod.allCases.enumerated()), id: \.element.id) { index, method in
                Button {
                    withAnimation(Design.Animation.springQuick) {
                        selectedMethod = method
                    }
                } label: {
                    methodRow(method: method)
                }
                .buttonStyle(ScalePressStyle())

                if index < ContactMethod.allCases.count - 1 {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.xs)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
    }

    @ViewBuilder
    private func methodRow(method: ContactMethod) -> some View {
        HStack(spacing: 12) {
            Image(systemName: method.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Design.Colors.teal)
                .frame(width: 24)

            Text(method.localizedLabel)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 14)
        .contentShape(.rect)
    }

    // MARK: - Input Section

    @ViewBuilder
    private func inputSection(method: ContactMethod) -> some View {
        VStack(spacing: Design.Spacing.lg) {
            // Back to method selection
            Button {
                withAnimation(Design.Animation.springQuick) {
                    selectedMethod = nil
                    inputValue = ""
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                }
                .foregroundStyle(Design.Colors.teal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Method header
            VStack(spacing: Design.Spacing.sm) {
                Image(systemName: method.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Design.Colors.teal)

                Text("Enter your \(method.localizedLabel)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }

            // Input field
            VStack(alignment: .leading, spacing: Design.Spacing.xs) {
                TextField(String(localized: method.placeholder), text: $inputValue)
                    .font(.system(.body, design: .rounded))
                    #if os(iOS)
                    .keyboardType(method.keyboardType)
                    .textInputAutocapitalization(method == .email ? .never : .words)
                    #endif
                    .autocorrectionDisabled()
                    .padding(Design.Spacing.md)
                    .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.md))

                if let hint = validationHint(for: method) {
                    Text(String(localized: hint))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.horizontal, Design.Spacing.xs)
                }
            }

            // Submit
            if showSuccess {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Design.Colors.teal)
                    Text("Contact linked successfully!")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Design.Colors.teal)
                }
                .transition(.scale.combined(with: .opacity))
            } else {
                PrimaryCTAButton(
                    title: "Link \(method.localizedLabel)",
                    isLoading: isSubmitting,
                    isDisabled: !method.validate(inputValue)
                ) {
                    Task { await submit(method: method) }
                }
            }
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.lg)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
    }

    // MARK: - Validation Hint

    private func validationHint(for method: ContactMethod) -> LocalizedStringResource? {
        guard !inputValue.isEmpty, !method.validate(inputValue) else { return nil }
        switch method {
        case .telegram:
            return "Enter a valid Telegram handle"
        case .whatsapp:
            return "Enter a valid phone number with country code"
        case .email:
            return "Enter a valid email address"
        }
    }

    // MARK: - Submit

    private func submit(method: ContactMethod) async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await accountManager.linkContact(method: method, value: inputValue)
            withAnimation(Design.Animation.springDefault) {
                showSuccess = true
            }
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
