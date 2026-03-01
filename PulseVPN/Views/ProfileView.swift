import SwiftUI

// MARK: - Profile View

struct ProfileView: View {
    let accountManager: AccountManager
    let rcService: RevenueCatService
    let syncService: SubscriptionSyncService
    let vpnManager: VPNManager
    let languageManager: LanguageManager

    @State private var copied = false
    @State private var showDeleteConfirmation = false
    @State private var showDeleteFinalConfirmation = false
    @State private var showLogoutConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showDeleteError = false
    @State private var showConnectAccountSheet = false

    // MARK: - Computed

    private var account: Account? { accountManager.account }

    private var accountId: String {
        account?.accountId ?? "---"
    }

    private var tierInfo: TierInfo {
        switch rcService.effectiveTier(fallbackAccount: account) {
        case .premium: return .premium
        case .pro: return .pro
        case .free: return .free
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            GlassEffectContainer {
                VStack(spacing: Design.Spacing.lg) {
                    // Account Card
                    VStack(alignment: .leading, spacing: Design.Spacing.md) {
                        // Header row: "Account ID" + tier badge
                        HStack {
                            Text("Account ID")
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(.secondary)

                            Spacer()

                            tierBadge
                        }

                        // The actual ID
                        Text(accountId)
                            .font(.system(.title3, design: .monospaced, weight: .bold))

                        // Action buttons
                        HStack(spacing: Design.Spacing.sm) {
                            copyButton
                            connectAccountButton
                        }
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: Design.CornerRadius.lg))

                    // Settings Card (Subscription + App Settings)
                    VStack(spacing: 0) {
                        NavigationLink {
                            SubscriptionView(accountManager: accountManager, rcService: rcService, syncService: syncService)
                        } label: {
                            settingsRow(icon: "creditcard.fill", color: Design.Colors.teal, title: "Subscription")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 40)
                        NavigationLink {
                            AppSettingsView(vpnManager: vpnManager, languageManager: languageManager)
                        } label: {
                            settingsRow(icon: "gearshape.fill", color: Design.Colors.textSecondary, title: "App Settings")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))

                    // Devices Card
                    NavigationLink {
                        DevicesView(accountManager: accountManager)
                    } label: {
                        settingsRow(icon: "iphone.gen3", color: Design.Colors.teal, title: "Devices")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))

                    // Support Card
                    VStack(spacing: 0) {
                        NavigationLink {
                            HelpSupportView()
                        } label: {
                            settingsRow(icon: "questionmark.circle.fill", color: Design.Colors.textSecondary, title: "Help & Support")
                        }
                        .buttonStyle(.plain)
                        Divider().padding(.leading, 40)
                        settingsButton(icon: "hand.raised.fill", color: Design.Colors.textSecondary, title: "Privacy Policy") {
                            openURL("https://www.dopplervpn.org/en/privacy")
                        }
                        Divider().padding(.leading, 40)
                        settingsButton(icon: "doc.text.fill", color: Design.Colors.textSecondary, title: "Terms of Service") {
                            openURL("https://www.dopplervpn.org/en/terms")
                        }
                    }
                    .padding(.horizontal, Design.Spacing.md)
                    .padding(.vertical, Design.Spacing.xs)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))

                    // Delete Account + Log Out
                    VStack(spacing: Design.Spacing.sm) {
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            Text("Delete Account")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.red.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())

                        Button {
                            showLogoutConfirmation = true
                        } label: {
                            Text("Log Out")
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(.red, in: Capsule())
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                    .padding(.top, Design.Spacing.sm)

                    // Version Footer
                    VStack(spacing: 2) {
                        Text("Doppler VPN")
                        Text("Version \(appVersion)")
                    }
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.top, Design.Spacing.xs)
                }
                .padding(.horizontal, Design.Spacing.md)
                .padding(.vertical, Design.Spacing.md)
            }
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                showDeleteFinalConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your account and all associated data. This action cannot be undone.")
        }
        .confirmationDialog(
            "Are you sure?",
            isPresented: $showDeleteFinalConfirmation,
            titleVisibility: .visible
        ) {
            Button("Yes, Delete Everything", role: .destructive) {
                Task { await performDeleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is your last chance. Your account, servers, and subscription data will be permanently removed.")
        }
        .alert("Cannot Delete Account", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "An error occurred.")
        }
        .sheet(isPresented: $showConnectAccountSheet) {
            ConnectAccountSheet(accountManager: accountManager)
                .presentationDetents([.medium])
        }
        .navigationTitle("Profile")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .confirmationDialog(
            "Log Out",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                accountManager.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need your Account ID to sign back in.")
        }
    }

    // MARK: - Copy Button

    @ViewBuilder
    private var copyButton: some View {
        Button {
            copyAccountId()
        } label: {
            Label(
                copied ? "Copied" : "Copy",
                systemImage: copied ? "checkmark" : "doc.on.doc"
            )
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(copied ? .green : Design.Colors.teal)
        #if os(iOS)
        .sensoryFeedback(.impact(weight: .light), trigger: copied)
        #endif
    }

    // MARK: - Connect Account Button

    @ViewBuilder
    private var connectAccountButton: some View {
        Button {
            showConnectAccountSheet = true
        } label: {
            Label(
                account?.hasLinkedContact == true ? "Linked" : "Link",
                systemImage: account?.hasLinkedContact == true ? "checkmark.circle.fill" : "link"
            )
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(Design.Colors.teal)
    }

    // MARK: - Tier Badge

    @ViewBuilder
    private var tierBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: tierInfo.icon)
                .font(.system(size: 11, weight: .bold))
            Text(tierInfo.label)
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tierInfo.color, in: Capsule())
    }

    // MARK: - Settings Row (display only)

    @ViewBuilder
    private func settingsRow(icon: String, color: Color, title: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
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

    // MARK: - Settings Button (tappable)

    @ViewBuilder
    private func settingsButton(icon: String, color: Color, title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsRow(icon: icon, color: color, title: title)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func openURL(_ urlString: String) {
        #if os(iOS)
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
        #elseif os(macOS)
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
        #endif
    }

    private func performDeleteAccount() async {
        // Check if user has an active subscription (RC + Supabase fallback)
        if rcService.effectiveTier(fallbackAccount: account) != .free {
            deleteError = String(localized: "You have an active subscription. Please cancel it in the App Store before deleting your account.")
            showDeleteError = true
            return
        }

        isDeleting = true
        defer { isDeleting = false }

        do {
            try await accountManager.deleteAccount()
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
        }
    }

    private func copyAccountId() {
        guard !accountId.isEmpty, accountId != "---" else { return }
        #if os(iOS)
        UIPasteboard.general.string = accountId
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(accountId, forType: .string)
        #endif
        withAnimation {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Design.Animation.springQuick, value: configuration.isPressed)
    }
}

// MARK: - Tier Info

private enum TierInfo {
    case free, pro, premium

    var planName: String {
        switch self {
        case .free: String(localized: "Free Plan")
        case .pro: String(localized: "Pro Plan")
        case .premium: String(localized: "Premium Plan")
        }
    }

    var label: String {
        switch self {
        case .free: String(localized: "FREE")
        case .pro: String(localized: "PRO")
        case .premium: String(localized: "PREMIUM")
        }
    }

    var subtitle: String {
        switch self {
        case .free: String(localized: "Upgrade for premium servers")
        case .pro: String(localized: "Active subscription")
        case .premium: String(localized: "All features unlocked")
        }
    }

    var icon: String {
        switch self {
        case .free: "shield"
        case .pro: "shield.checkered"
        case .premium: "crown.fill"
        }
    }

    var color: Color {
        switch self {
        case .free: .secondary
        case .pro: Design.Colors.teal
        case .premium: .orange
        }
    }
}

// MARK: - Previews

#Preview("Profile") {
    NavigationStack {
        ProfileView(accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService(), vpnManager: VPNManager(), languageManager: LanguageManager.shared)
    }
}

#Preview("Profile Dark") {
    NavigationStack {
        ProfileView(accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService(), vpnManager: VPNManager(), languageManager: LanguageManager.shared)
    }
    .preferredColorScheme(.dark)
}
