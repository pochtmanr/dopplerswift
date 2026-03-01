import SwiftUI
import RevenueCat

@main
struct PulseVPNApp: App {
    @State private var vpnManager = VPNManager()
    @State private var accountManager = AccountManager()
    @State private var rcService = RevenueCatService()
    @State private var syncService = SubscriptionSyncService()
    @State private var languageManager = LanguageManager.shared

    init() {
        // Configure RevenueCat SDK globally (before any Purchases.shared calls).
        // This is a static SDK setup — the @State rcService instance handles
        // all subsequent calls and state tracking.
        if let apiKey = RevenueCatConfig.apiKey {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(vpnManager: vpnManager, accountManager: accountManager, rcService: rcService, syncService: syncService, languageManager: languageManager)
                .environment(\.locale, languageManager.effectiveLocale)
                .environment(\.layoutDirection, languageManager.layoutDirection)
                .id(languageManager.selectedLanguage)
                .task {
                    // One-time setup: RC delegate + initial account restore
                    rcService.configure()
                    await accountManager.initialize()
                    // Account-specific RC login + sync is handled by onChange below
                }
                .onChange(of: accountManager.account?.accountId, initial: true) { _, newValue in
                    guard rcService.isConfigured else { return }
                    guard let accountId = newValue else { return }
                    Task {
                        await rcService.logIn(accountId: accountId)
                        await rcService.fetchOfferings()
                        await syncAndHandleRejection(accountId: accountId)
                    }
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task {
                        await rcService.refreshCustomerInfo()
                        if let accountId = accountManager.account?.accountId {
                            await syncAndHandleRejection(accountId: accountId)
                        }
                    }
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 650)
        #endif
    }

    /// Syncs subscription to Supabase and handles ownership rejection/approval.
    @MainActor
    private func syncAndHandleRejection(accountId: String) async {
        guard let customerInfo = rcService.customerInfo else { return }
        let syncResult = await syncService.sync(
            accountId: accountId,
            customerInfo: customerInfo,
            tier: rcService.currentTier
        )
        switch syncResult {
        case .rejected(let owner):
            rcService.markSubscriptionRejected(owner: owner)
        case .success:
            rcService.clearSubscriptionRejection()
        case .skipped, .error:
            break
        }
    }
}

// MARK: - Root View

struct RootView: View {
    let vpnManager: VPNManager
    let accountManager: AccountManager
    let rcService: RevenueCatService
    let syncService: SubscriptionSyncService
    let languageManager: LanguageManager

    var body: some View {
        Group {
            if accountManager.isInitializing {
                launchScreen
            } else if !accountManager.isOnboardingComplete {
                onboardingFlow
            } else if !accountManager.isAuthenticated {
                accountFlow
            } else {
                ContentView(vpnManager: vpnManager, accountManager: accountManager, rcService: rcService, syncService: syncService, languageManager: languageManager)
            }
        }
        .animation(Design.Animation.springDefault, value: accountManager.isInitializing)
        .animation(Design.Animation.springDefault, value: accountManager.isOnboardingComplete)
        .animation(Design.Animation.springDefault, value: accountManager.isAuthenticated)
    }

    @ViewBuilder
    private var launchScreen: some View {
        ZStack {
            Design.Colors.surfaceBackground
                .ignoresSafeArea()

            VStack(spacing: Design.Spacing.md) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .background(
                        LinearGradient(
                            colors: [Color.teal, Color.teal.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.teal.opacity(0.3), radius: 12, y: 6)

                ProgressView()
                    .controlSize(.regular)
                    .tint(.secondary)
            }
        }
    }

    @ViewBuilder
    private var onboardingFlow: some View {
        WelcomeView {
            accountManager.isOnboardingComplete = true
        }
    }

    @ViewBuilder
    private var accountFlow: some View {
        NavigationStack {
            AccountSetupView(accountManager: accountManager, rcService: rcService, syncService: syncService)
                .navigationTitle("Account")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
}
