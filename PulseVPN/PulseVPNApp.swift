import SwiftUI
import RevenueCat

@main
struct PulseVPNApp: App {
    @State private var vpnManager = VPNManager()
    @State private var accountManager = AccountManager()
    @State private var rcService = RevenueCatService()
    @State private var syncService = SubscriptionSyncService()

    init() {
        // Configure RevenueCat SDK globally (before any Purchases.shared calls).
        // This is a static SDK setup — the @State rcService instance handles
        // all subsequent calls and state tracking.
        if let apiKey = RevenueCatConfig.apiKey {
            Purchases.logLevel = .debug
            Purchases.configure(withAPIKey: apiKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(vpnManager: vpnManager, accountManager: accountManager, rcService: rcService)
                .task {
                    await accountManager.initialize()

                    // Set up RC delegate and link identity
                    rcService.configure()
                    if let accountId = accountManager.account?.accountId {
                        await rcService.logIn(accountId: accountId)
                    }

                    // Fetch offerings
                    await rcService.fetchOfferings()

                    // Sync subscription to Supabase if active
                    if let accountId = accountManager.account?.accountId,
                       let customerInfo = rcService.customerInfo {
                        await syncService.sync(
                            accountId: accountId,
                            customerInfo: customerInfo,
                            tier: rcService.currentTier
                        )
                    }
                }
                #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task {
                        await rcService.refreshCustomerInfo()

                        // Re-sync on foreground
                        if let accountId = accountManager.account?.accountId,
                           let customerInfo = rcService.customerInfo {
                            await syncService.sync(
                                accountId: accountId,
                                customerInfo: customerInfo,
                                tier: rcService.currentTier
                            )
                        }
                    }
                }
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 650)
        #endif
    }
}

// MARK: - Root View

struct RootView: View {
    let vpnManager: VPNManager
    let accountManager: AccountManager
    let rcService: RevenueCatService

    var body: some View {
        Group {
            if !accountManager.isOnboardingComplete {
                onboardingFlow
            } else if !accountManager.isAuthenticated {
                accountFlow
            } else {
                ContentView(vpnManager: vpnManager, accountManager: accountManager, rcService: rcService)
            }
        }
        .animation(Design.Animation.springDefault, value: accountManager.isOnboardingComplete)
        .animation(Design.Animation.springDefault, value: accountManager.isAuthenticated)
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
            AccountSetupView(accountManager: accountManager)
                .navigationTitle("Account")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
}
