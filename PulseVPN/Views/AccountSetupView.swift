import SwiftUI

// MARK: - Account Mode

enum AccountMode: Equatable {
    case choice
    case create
    case login
}

// MARK: - Account Setup View

struct AccountSetupView: View {
    let accountManager: AccountManager

    // MARK: - State

    @State private var mode: AccountMode = .choice
    @State private var generatedAccountId: String?
    @State private var loginInput: String = ""
    @State private var copied = false
    @State private var showShareSheet = false

    private var isLoginValid: Bool {
        AccountInputFormatter.isValid(loginInput)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    modeContent
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.xxl)
            }
        }
        .animation(Design.Animation.springDefault, value: mode)
        .animation(Design.Animation.springDefault, value: generatedAccountId)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundGradient: some View {
        ZStack {
            Design.Colors.surfaceBackground
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Design.Colors.accent.opacity(0.05),
                    Color.clear
                ],
                center: .top,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Mode Router

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .choice:
            choiceContent
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        case .create:
            createContent
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
        case .login:
            loginContent
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
        }
    }

    // MARK: - Choice Mode

    @ViewBuilder
    private var choiceContent: some View {
        VStack(spacing: Design.Spacing.lg) {
            choiceHeader
            choiceCards
            deviceInfoPill
        }
    }

    @ViewBuilder
    private var choiceHeader: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Get Started")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)

            Text("Create a new account or login with an existing ID")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var choiceCards: some View {
        VStack(spacing: Design.Spacing.md) {
            choiceCard(
                icon: "key.fill",
                iconColor: Design.Colors.accent,
                title: "Create Account",
                description: "Get a unique ID to use across all your devices"
            ) {
                withAnimation(Design.Animation.springDefault) {
                    mode = .create
                }
            }

            choiceCard(
                icon: "iphone.gen3",
                iconColor: .green,
                title: "Login",
                description: "Enter your existing account ID to continue"
            ) {
                withAnimation(Design.Animation.springDefault) {
                    mode = .login
                }
            }
        }
    }

    @ViewBuilder
    private func choiceCard(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Design.Spacing.md) {
                iconBadge(icon: icon, color: iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text(description)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Design.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .padding(Design.Spacing.md)
            .background(Design.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.separator.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleCardButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }

    @ViewBuilder
    private var deviceInfoPill: some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "shield.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Design.Colors.textTertiary)

            Text("Your account works on up to 10 devices")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm + 2)
        .background(Design.Colors.surfaceCard, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Design.Colors.separator.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Create Mode

    @ViewBuilder
    private var createContent: some View {
        if generatedAccountId != nil {
            createResultContent
        } else {
            createPromptContent
        }
    }

    @ViewBuilder
    private var createPromptContent: some View {
        VStack(spacing: Design.Spacing.lg) {
            createPromptHeader
            previewCard
            createPromptActions

            if let error = accountManager.errorMessage {
                errorBanner(error)
            }
        }
    }

    @ViewBuilder
    private var createPromptHeader: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Create Account")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)

            Text("We'll generate a unique ID for you. Save it to use on other devices.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var previewCard: some View {
        Text("VPN-XXXX-XXXX-XXXX")
            .font(.system(.body, design: .monospaced, weight: .medium))
            .foregroundStyle(Design.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.lg)
            .padding(.horizontal, Design.Spacing.md)
            .background(Design.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.separator.opacity(0.3), lineWidth: 1)
            )
    }

    @ViewBuilder
    private var createPromptActions: some View {
        VStack(spacing: Design.Spacing.md) {
            generateButton
            backButton
        }
    }

    @ViewBuilder
    private var generateButton: some View {
        Button {
            handleGenerate()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                if accountManager.isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                } else {
                    Image(systemName: "key.fill")
                        .font(.system(size: 14, weight: .semibold))
                }

                Text("Generate My Account ID")
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
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
        .buttonStyle(ScaleCardButtonStyle())
        .disabled(accountManager.isLoading)
        .opacity(accountManager.isLoading ? 0.7 : 1.0)
        .accessibilityLabel("Generate My Account ID")
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .medium), trigger: generatedAccountId)
        #endif
    }

    // MARK: - Create Result

    @ViewBuilder
    private var createResultContent: some View {
        VStack(spacing: Design.Spacing.lg) {
            createResultHeader
            accountIdDisplayCard
            actionButtonRow
            warningCard
            continueButton

            if let error = accountManager.errorMessage {
                errorBanner(error)
            }
        }
    }

    @ViewBuilder
    private var createResultHeader: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Your Account ID")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)

            Text("Save this ID! You'll need it to access your account on other devices.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accountIdDisplayCard: some View {
        Text(generatedAccountId ?? "")
            .font(.system(.title2, design: .monospaced, weight: .bold))
            .foregroundStyle(Design.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xl)
            .padding(.horizontal, Design.Spacing.md)
            .background(Design.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                    .strokeBorder(Design.Colors.separator.opacity(0.3), lineWidth: 1)
            )
            .accessibilityLabel("Account ID: \(generatedAccountId ?? "")")
    }

    @ViewBuilder
    private var actionButtonRow: some View {
        HStack(spacing: Design.Spacing.md) {
            copyButton
            shareButton
        }
    }

    @ViewBuilder
    private var copyButton: some View {
        Button {
            handleCopy()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))

                Text(copied ? "Copied" : "Copy")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .foregroundStyle(copied ? .green : Design.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.sm + 4)
            .background(
                copied ? Color.green.opacity(0.12) : Design.Colors.surfaceCardHover,
                in: RoundedRectangle(cornerRadius: Design.CornerRadius.md)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied to clipboard" : "Copy account ID")
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .medium), trigger: copied)
        #endif
    }

    @ViewBuilder
    private var shareButton: some View {
        if let accountId = generatedAccountId {
            ShareLink(item: accountId) {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))

                    Text("Share")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                .foregroundStyle(Design.Colors.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm + 4)
                .background(Design.Colors.surfaceCardHover, in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share account ID")
        }
    }

    @ViewBuilder
    private var warningCard: some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            Text("This is your only way to access your account. Store it securely.")
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(Design.Spacing.md)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var continueButton: some View {
        Button {
            accountManager.isOnboardingComplete = true
        } label: {
            Text("Continue")
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
        .buttonStyle(ScaleCardButtonStyle())
        .accessibilityLabel("Continue to app")
    }

    // MARK: - Login Mode

    @ViewBuilder
    private var loginContent: some View {
        VStack(spacing: Design.Spacing.lg) {
            loginHeader
            loginInputCard
            loginActions

            if let error = accountManager.errorMessage {
                errorBanner(error)
            }
        }
    }

    @ViewBuilder
    private var loginHeader: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Welcome Back")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Design.Colors.textPrimary)

            Text("Enter your Account ID to continue")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var loginInputCard: some View {
        VStack(spacing: Design.Spacing.sm) {
            HStack(spacing: Design.Spacing.sm) {
                TextField("VPN-XXXX-XXXX-XXXX", text: $loginInput)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.characters)
                    #endif
                    .onChange(of: loginInput) { _, newValue in
                        let formatted = AccountInputFormatter.format(newValue)
                        if formatted != newValue {
                            loginInput = formatted
                        }
                    }

                Button {
                    handlePaste()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Design.Colors.accent)
                        .frame(width: 36, height: 36)
                        .background(Design.Colors.accent.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste from clipboard")
            }

            if !loginInput.isEmpty && loginInput.count > 4 && !isLoginValid {
                Text("Format: VPN-XXXX-XXXX-XXXX")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Design.Colors.textTertiary)
                    .transition(.opacity)
            }
        }
        .padding(Design.Spacing.md)
        .background(Design.Colors.surfaceCard, in: RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.lg)
                .strokeBorder(
                    isLoginValid
                        ? Design.Colors.accent.opacity(0.4)
                        : Design.Colors.separator.opacity(0.3),
                    lineWidth: 1
                )
        )
        .animation(Design.Animation.springQuick, value: isLoginValid)
    }

    @ViewBuilder
    private var loginActions: some View {
        VStack(spacing: Design.Spacing.md) {
            loginButton
            backButton
        }
    }

    @ViewBuilder
    private var loginButton: some View {
        Button {
            handleLogin()
        } label: {
            HStack(spacing: Design.Spacing.sm) {
                if accountManager.isLoading {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }

                Text("Login")
                    .font(.system(.body, design: .rounded, weight: .bold))
            }
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
            .shadow(color: Design.Colors.accent.opacity(isLoginValid ? 0.3 : 0.0), radius: 12, y: 6)
        }
        .buttonStyle(ScaleCardButtonStyle())
        .disabled(!isLoginValid || accountManager.isLoading)
        .opacity(isLoginValid ? 1.0 : 0.5)
        .accessibilityLabel("Login with account ID")
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .medium), trigger: accountManager.isAuthenticated)
        #endif
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var backButton: some View {
        Button {
            withAnimation(Design.Animation.springDefault) {
                accountManager.errorMessage = nil
                mode = .choice
                generatedAccountId = nil
                loginInput = ""
            }
        } label: {
            Text("Back")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go back")
    }

    @ViewBuilder
    private func iconBadge(icon: String, color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(color)
            .frame(width: 48, height: 48)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
                .lineLimit(3)

            Spacer()
        }
        .padding(Design.Spacing.md)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Design.CornerRadius.md)
                .strokeBorder(Color.red.opacity(0.2), lineWidth: 1)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func handleGenerate() {
        Task {
            await accountManager.createAccount()
            if let account = accountManager.account {
                withAnimation(Design.Animation.springDefault) {
                    generatedAccountId = account.accountId
                }
            }
        }
    }

    private func handleLogin() {
        Task {
            await accountManager.loginWithAccountId(loginInput)
            // If login succeeds, accountManager.isAuthenticated will become true
            // and the parent navigation will react accordingly
        }
    }

    private func handlePaste() {
        #if os(iOS)
        guard let pasted = UIPasteboard.general.string else { return }
        #elseif os(macOS)
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        #endif
        let formatted = AccountInputFormatter.format(pasted.trimmingCharacters(in: .whitespacesAndNewlines))
        withAnimation(Design.Animation.springQuick) {
            loginInput = formatted
        }
    }

    private func handleCopy() {
        guard let accountId = generatedAccountId else { return }
        #if os(iOS)
        UIPasteboard.general.string = accountId
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(accountId, forType: .string)
        #endif
        withAnimation(Design.Animation.springQuick) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(Design.Animation.springQuick) {
                copied = false
            }
        }
    }
}

// MARK: - Scale Card Button Style

private struct ScaleCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Design.Animation.springQuick, value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Choice") {
    AccountSetupView(accountManager: AccountManager())
}

#Preview("Choice Dark") {
    AccountSetupView(accountManager: AccountManager())
        .preferredColorScheme(.dark)
}
