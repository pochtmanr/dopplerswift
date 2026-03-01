import SwiftUI
import RevenueCat

// MARK: - Account Setup View

struct AccountSetupView: View {
    let accountManager: AccountManager
    let rcService: RevenueCatService
    let syncService: SubscriptionSyncService

    // MARK: - State

    @State private var showCreateSheet = false
    @State private var showLoginSheet = false
    @State private var generatedAccountId: String?
    @State private var loginInput: String = ""
    @State private var copied = false

    /// Detected owner account ID if this Apple ID has an existing subscription
    @State private var detectedOwnerAccountId: String?
    @State private var isCheckingSubscription = false

    private var isLoginValid: Bool {
        AccountInputFormatter.isValid(loginInput)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    choiceContent
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.xxl)
            }
        }
        .animation(Design.Animation.springDefault, value: detectedOwnerAccountId)
        .onAppear {
            // If redirected from a subscription ownership conflict,
            // pre-fill the original account ID and jump to login sheet.
            if let prefill = accountManager.consumePrefillAccountId() {
                loginInput = prefill
                showLoginSheet = true
            }

            // Re-check for existing subscription every time this view appears
            // (handles: first visit, returning after logout from new account, etc.)
            detectedOwnerAccountId = nil
            Task {
                await checkExistingSubscription()
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createSheetContent
        }
        .sheet(isPresented: $showLoginSheet) {
            loginSheetContent
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundGradient: some View {
        ZStack {
            Design.Colors.surfaceBackground
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Design.Colors.teal.opacity(0.05),
                    Color.clear
                ],
                center: .top,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Choice Content (Always Visible)

    @ViewBuilder
    private var choiceContent: some View {
        VStack(spacing: Design.Spacing.lg) {
            choiceHeader

            // Show detected subscription banner if this Apple ID has an active sub
            if let ownerId = detectedOwnerAccountId {
                existingSubscriptionBanner(ownerId: ownerId)
            } else if isCheckingSubscription {
                HStack(spacing: Design.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Checking for existing subscription...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
                .padding(.vertical, Design.Spacing.sm)
            }

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
                iconColor: Design.Colors.teal,
                title: "Create Account",
                description: "Get a unique ID to use across all your devices"
            ) {
                accountManager.errorMessage = nil
                generatedAccountId = nil
                showCreateSheet = true
            }

            choiceCard(
                icon: "iphone.gen3",
                iconColor: .green,
                title: "Login",
                description: "Enter your existing account ID to continue"
            ) {
                accountManager.errorMessage = nil
                loginInput = ""
                showLoginSheet = true
            }
        }
    }

    @ViewBuilder
    private func choiceCard(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        description: LocalizedStringKey,
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
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
        .buttonStyle(ScalePressStyle())
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
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: - Create Account Sheet

    @ViewBuilder
    private var createSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    if generatedAccountId != nil {
                        createResultContent
                    } else {
                        createPromptContent
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .navigationTitle("Create Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showCreateSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .animation(Design.Animation.springDefault, value: generatedAccountId)
    }

    @ViewBuilder
    private var createPromptContent: some View {
        VStack(spacing: Design.Spacing.lg) {
            createPromptHeader
            previewCard
            generateButton

            if let error = accountManager.errorMessage {
                errorBanner(error)
            }
        }
    }

    @ViewBuilder
    private var createPromptHeader: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Generate Your ID")
                .font(.system(.title3, design: .rounded, weight: .bold))
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
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
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
                    colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: Design.Colors.teal.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(accountManager.isLoading)
        .opacity(accountManager.isLoading ? 0.7 : 1.0)
        .accessibilityLabel("Generate My Account ID")
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .medium), trigger: generatedAccountId)
        #endif
    }

    // MARK: - Create Result (inside create sheet)

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
                .font(.system(.title3, design: .rounded, weight: .bold))
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
            .foregroundStyle(Design.Colors.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.xl)
            .padding(.horizontal, Design.Spacing.md)
            .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
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
            .foregroundStyle(copied ? .green : Design.Colors.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Design.Spacing.sm + 4)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.md))
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
                .foregroundStyle(Design.Colors.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm + 4)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.md))
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
            showCreateSheet = false
            accountManager.isOnboardingComplete = true
        } label: {
            Text("Continue")
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(
                    LinearGradient(
                        colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Design.Colors.teal.opacity(0.3), radius: 12, y: 6)
        }
        .buttonStyle(ScalePressStyle())
        .accessibilityLabel("Continue to app")
    }

    // MARK: - Login Sheet

    @ViewBuilder
    private var loginSheetContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.Spacing.lg) {
                    loginHeader
                    loginInputCard
                    loginButton

                    if let error = accountManager.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, Design.Spacing.lg)
                .padding(.top, Design.Spacing.lg)
                .padding(.bottom, Design.Spacing.xxl)
            }
            .navigationTitle("Login")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showLoginSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
        .animation(Design.Animation.springQuick, value: isLoginValid)
    }

    @ViewBuilder
    private var loginHeader: some View {
        VStack(alignment: .leading, spacing: Design.Spacing.sm) {
            Text("Welcome Back")
                .font(.system(.title3, design: .rounded, weight: .bold))
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
                        .foregroundStyle(Design.Colors.teal)
                        .frame(width: 36, height: 36)
                        .background(Design.Colors.teal.opacity(0.1), in: Circle())
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
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
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
                    colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
            .shadow(color: Design.Colors.teal.opacity(isLoginValid ? 0.3 : 0.0), radius: 12, y: 6)
        }
        .buttonStyle(ScalePressStyle())
        .disabled(!isLoginValid || accountManager.isLoading)
        .opacity(isLoginValid ? 1.0 : 0.5)
        .accessibilityLabel("Login with account ID")
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .medium), trigger: accountManager.isAuthenticated)
        #endif
    }

    // MARK: - Shared Components

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

    // MARK: - Existing Subscription Detection

    /// Checks RC for an active subscription on this Apple ID,
    /// then queries Supabase to find which account owns it.
    private func checkExistingSubscription() async {
        guard rcService.isConfigured else { return }

        isCheckingSubscription = true
        defer { isCheckingSubscription = false }

        // Fetch current customer info from RC (anonymous or cached identity)
        do {
            let info = try await Purchases.shared.customerInfo()

            // Check if there's an active entitlement
            let entitlements = info.entitlements.active
            let entitlement = entitlements[RCEntitlements.premium] ?? entitlements[RCEntitlements.pro]
            guard let entitlement else { return }

            // Build the transaction ID to look up the owner
            let productId = entitlement.productIdentifier
            let dateString: String
            if let originalDate = entitlement.originalPurchaseDate {
                dateString = ISO8601DateFormatter().string(from: originalDate)
            } else {
                dateString = "unknown"
            }
            let originalTransactionId = "\(productId)_\(dateString)"

            // Ask Supabase who owns this transaction
            // We pass a dummy account ID -- verify_restore will tell us the owner
            let verification = await syncService.verifyRestore(
                accountId: "CHECK_ONLY",
                originalTransactionId: originalTransactionId
            )

            switch verification {
            case .rejected(let owner):
                withAnimation(Design.Animation.springDefault) {
                    detectedOwnerAccountId = owner
                }
            case .allowed, .error:
                // No existing owner, or check failed -- proceed normally
                break
            }
        } catch {
            NSLog("[AccountSetupView] Failed to check existing subscription: %@", error.localizedDescription)
        }
    }

    // MARK: - Existing Subscription Banner

    @ViewBuilder
    private func existingSubscriptionBanner(ownerId: String) -> some View {
        VStack(spacing: Design.Spacing.md) {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Design.Colors.teal)
                    .frame(width: 44, height: 44)
                    .background(Design.Colors.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pro Subscription Found")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Design.Colors.textPrimary)

                    Text("Your Apple ID has an active subscription linked to:")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Design.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Account ID display
            Text(ownerId)
                .font(.system(.body, design: .monospaced, weight: .bold))
                .foregroundStyle(Design.Colors.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.md)
                .background(Design.Colors.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: Design.CornerRadius.md))

            // Login CTA — log in directly, skip the login sheet
            Button {
                loginInput = ownerId
                handleLogin()
            } label: {
                HStack(spacing: Design.Spacing.sm) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Log In to \(ownerId)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Design.Colors.teal, Design.Colors.teal.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: Design.Colors.teal.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(ScalePressStyle())
        }
        .padding(Design.Spacing.md)
        .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

// MARK: - Previews

#Preview("Choice") {
    AccountSetupView(accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService())
}

#Preview("Choice Dark") {
    AccountSetupView(accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService())
        .preferredColorScheme(.dark)
}
