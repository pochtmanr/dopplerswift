import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    let vpnManager: VPNManager
    let accountManager: AccountManager
    let rcService: RevenueCatService
    let syncService: SubscriptionSyncService
    let languageManager: LanguageManager

    @State private var servers: [ServerConfig] = []
    @State private var selectedServerID: UUID?
    @State private var showAddServer = false
    @State private var showServerList = false
    @State private var selectedTab: AppTab = .vpn

    // Smart Routing state
    @State private var smartRoutingEnabled: Bool = ConfigStore.loadSmartRoutingEnabled()
    @State private var smartRoutingCountry: String = ConfigStore.loadSmartRoutingCountry() ?? ""
    @State private var smartRoutingCustomDomains: [String] = ConfigStore.loadSmartRoutingCustomDomains()
    @State private var detectedCountryCode: String?

    // Bypass category toggles
    @State private var bypassTLDWebsites: Bool = ConfigStore.loadBypassTLDWebsites()
    @State private var bypassGovernmentBanking: Bool = ConfigStore.loadBypassGovernmentBanking()

    @State private var cloudServers: [SupabaseServer] = []
    @State private var isLoadingCloud = false
    @State private var cloudError: String?
    @State private var showPaywall = false
    @State private var paywallPending = false
    @State private var conflictOwnerId: String?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - Computed Properties

    /// Unified Pro check: RC first, Supabase fallback (handles web/Stripe subs)
    private var isEffectivelyPro: Bool {
        rcService.isEffectivelyPro(fallbackAccount: accountManager.account)
    }

    private var selectedServer: ServerConfig? {
        servers.first { $0.id == selectedServerID }
    }

    /// The effective country code for smart routing (user-selected or auto-detected).
    private var effectiveSmartRoutingCountry: String? {
        let code = smartRoutingCountry.isEmpty ? detectedCountryCode : smartRoutingCountry
        return smartRoutingEnabled ? code : nil
    }

    // MARK: - Body

    var body: some View {
        #if os(macOS)
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear { performInitialLoad() }
        #elseif os(iOS)
        if horizontalSizeClass == .compact {
            compactLayout
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .onAppear { performInitialLoad() }
        }
        #endif
    }

    // MARK: - Sidebar (iPad / macOS)

    @ViewBuilder
    private var sidebar: some View {
        List {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title, systemImage: tab.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .foregroundStyle(selectedTab == tab ? Design.Colors.teal : .primary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selectedTab == tab ? Design.Colors.teal.opacity(0.15) : .clear)
                        .padding(.horizontal, 4)
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Doppler VPN")
        .tint(Design.Colors.teal)
        .onChange(of: servers) {
            ConfigStore.saveServers(servers)
        }
        .onChange(of: selectedServerID) {
            ConfigStore.saveSelectedServerID(selectedServerID)
        }
    }

    // MARK: - Detail (iPad / macOS)

    @ViewBuilder
    private var detail: some View {
        NavigationStack {
            Group {
                switch selectedTab {
                case .vpn:
                    HomeView(
                        vpnManager: vpnManager,
                        selectedServer: selectedServer,
                        onConnectAndConvert: convertAndConnect,
                        onServerTap: { showServerList = true },
                        onSmartRouteTap: { selectedTab = .smartRoute },
                        smartRoutingEnabled: $smartRoutingEnabled,
                        smartRoutingCountry: effectiveSmartRoutingCountry
                    )
                case .smartRoute:
                    SmartRoutingView(
                        isEnabled: $smartRoutingEnabled,
                        selectedCountryCode: $smartRoutingCountry,
                        detectedCountryCode: detectedCountryCode,
                        vpnStatus: vpnManager.status,
                        customDomains: $smartRoutingCustomDomains,
                        bypassTLDWebsites: $bypassTLDWebsites,
                        bypassGovernmentBanking: $bypassGovernmentBanking
                    )
                case .profile:
                    ProfileView(accountManager: accountManager, rcService: rcService, syncService: syncService, vpnManager: vpnManager, languageManager: languageManager)
                }
            }
        }
        .id(selectedTab)
        .sheet(isPresented: $showServerList) {
            serverListSheet
        }
        .sheet(isPresented: $showAddServer) {
            addServerSheet
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(rcService: rcService, isPresented: $showPaywall)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
        }
        .sheet(item: $conflictOwnerId) { owner in
            SubscriptionConflictSheet(
                ownerAccountId: owner,
                onSwitchAccount: { ownerId in
                    conflictOwnerId = nil
                    accountManager.prefillAccountId = ownerId
                    accountManager.switchAccount()
                },
                onDismiss: { conflictOwnerId = nil },
                onContactSupport: {
                    conflictOwnerId = nil
                    openSupportEmail()
                }
            )
            .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: rcService.subscriptionRejectedByServer, initial: true) {
            if rcService.subscriptionRejectedByServer, let owner = rcService.rejectedOwnerAccountId {
                conflictOwnerId = owner
            }
        }
        .onChange(of: smartRoutingEnabled) {
            if smartRoutingEnabled && !isEffectivelyPro {
                smartRoutingEnabled = false
                showPaywall = true
                return
            }
            ConfigStore.saveSmartRoutingEnabled(smartRoutingEnabled)
            reconnectIfNeeded()
        }
        .onChange(of: smartRoutingCountry) {
            ConfigStore.saveSmartRoutingCountry(smartRoutingCountry)
            reconnectIfNeeded()
        }
        .onChange(of: smartRoutingCustomDomains) {
            ConfigStore.saveSmartRoutingCustomDomains(smartRoutingCustomDomains)
            reconnectIfNeeded()
        }
        .onChange(of: bypassTLDWebsites) {
            ConfigStore.saveBypassTLDWebsites(bypassTLDWebsites)
            reconnectIfNeeded()
        }
        .onChange(of: bypassGovernmentBanking) {
            ConfigStore.saveBypassGovernmentBanking(bypassGovernmentBanking)
            reconnectIfNeeded()
        }
        .onChange(of: showServerList) {
            if !showServerList && paywallPending {
                paywallPending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showPaywall = true
                }
            }
        }
    }

    // MARK: - Compact (iPhone) Layout

    #if os(iOS)
    @ViewBuilder
    private var compactLayout: some View {
        TabView(selection: $selectedTab) {
            Tab("VPN", systemImage: "shield.fill", value: .vpn) {
                NavigationStack {
                    HomeView(
                        vpnManager: vpnManager,
                        selectedServer: selectedServer,
                        onConnectAndConvert: convertAndConnect,
                        onServerTap: { showServerList = true },
                        onSmartRouteTap: { selectedTab = .smartRoute },
                        smartRoutingEnabled: $smartRoutingEnabled,
                        smartRoutingCountry: effectiveSmartRoutingCountry
                    )
                    .navigationTitle("Doppler VPN")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showAddServer = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .tint(Design.Colors.teal)
                            .accessibilityLabel("Add Server")
                        }
                    }
                    .sheet(isPresented: $showServerList) {
                        serverListSheet
                    }
                    .sheet(isPresented: $showAddServer) {
                        addServerSheet
                    }
                }
            }

            Tab("Smart Route", systemImage: "arrow.triangle.branch", value: .smartRoute) {
                NavigationStack {
                    SmartRoutingView(
                        isEnabled: $smartRoutingEnabled,
                        selectedCountryCode: $smartRoutingCountry,
                        detectedCountryCode: detectedCountryCode,
                        vpnStatus: vpnManager.status,
                        customDomains: $smartRoutingCustomDomains,
                        bypassTLDWebsites: $bypassTLDWebsites,
                        bypassGovernmentBanking: $bypassGovernmentBanking
                    )
                    .navigationTitle("Smart Route")
                    .navigationBarTitleDisplayMode(.large)
                }
            }

            Tab("Profile", systemImage: "person.circle", value: .profile) {
                NavigationStack {
                    ProfileView(accountManager: accountManager, rcService: rcService, syncService: syncService, vpnManager: vpnManager, languageManager: languageManager)
                }
            }
        }
        .tint(Design.Colors.teal)
        .sheet(isPresented: $showPaywall) {
            PaywallView(rcService: rcService, isPresented: $showPaywall)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.clear)
        }
        .sheet(item: $conflictOwnerId) { owner in
            SubscriptionConflictSheet(
                ownerAccountId: owner,
                onSwitchAccount: { ownerId in
                    conflictOwnerId = nil
                    accountManager.prefillAccountId = ownerId
                    accountManager.switchAccount()
                },
                onDismiss: { conflictOwnerId = nil },
                onContactSupport: {
                    conflictOwnerId = nil
                    openSupportEmail()
                }
            )
            .presentationBackground(.ultraThinMaterial)
        }
        .onChange(of: rcService.subscriptionRejectedByServer, initial: true) {
            if rcService.subscriptionRejectedByServer, let owner = rcService.rejectedOwnerAccountId {
                conflictOwnerId = owner
            }
        }
        .onChange(of: servers) {
            ConfigStore.saveServers(servers)
        }
        .onChange(of: selectedServerID) {
            ConfigStore.saveSelectedServerID(selectedServerID)
        }
        .onChange(of: smartRoutingEnabled) {
            if smartRoutingEnabled && !isEffectivelyPro {
                smartRoutingEnabled = false
                showPaywall = true
                return
            }
            ConfigStore.saveSmartRoutingEnabled(smartRoutingEnabled)
            reconnectIfNeeded()
        }
        .onChange(of: smartRoutingCountry) {
            ConfigStore.saveSmartRoutingCountry(smartRoutingCountry)
            reconnectIfNeeded()
        }
        .onChange(of: smartRoutingCustomDomains) {
            ConfigStore.saveSmartRoutingCustomDomains(smartRoutingCustomDomains)
            reconnectIfNeeded()
        }
        .onChange(of: bypassTLDWebsites) {
            ConfigStore.saveBypassTLDWebsites(bypassTLDWebsites)
            reconnectIfNeeded()
        }
        .onChange(of: bypassGovernmentBanking) {
            ConfigStore.saveBypassGovernmentBanking(bypassGovernmentBanking)
            reconnectIfNeeded()
        }
        .onChange(of: showServerList) {
            if !showServerList && paywallPending {
                paywallPending = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showPaywall = true
                }
            }
        }
        .onAppear { performInitialLoad() }
    }
    #endif

    // MARK: - Server List Sheet (iPhone)

    @ViewBuilder
    private var serverListSheet: some View {
        NavigationStack {
            ServerListView(
                servers: $servers,
                selectedServerID: $selectedServerID,
                cloudServers: cloudServers,
                isLoadingCloud: isLoadingCloud,
                cloudError: cloudError,
                isUserPro: isEffectivelyPro,
                onRefreshCloud: { await loadCloudServers() },
                onSelectCloudServer: { server in
                    if server.isPremium == true && !isEffectivelyPro {
                        paywallPending = true
                        showServerList = false
                    } else {
                        selectCloudServer(server)
                        showServerList = false
                    }
                }
            )
            .navigationTitle("Servers")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showServerList = false
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showServerList = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAddServer = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Add Server Sheet

    @ViewBuilder
    private var addServerSheet: some View {
        NavigationStack {
            ConfigInputView(
                onAddServer: { config in
                    let server = ServerConfig(vlessConfig: config, source: .manual)
                    servers.append(server)
                    if servers.count == 1 {
                        selectedServerID = server.id
                    }
                    showAddServer = false
                },
                onLoadSubscription: { configs in
                    let newServers = configs.map { ServerConfig(vlessConfig: $0, source: .manual) }
                    servers.append(contentsOf: newServers)
                    if selectedServerID == nil, let first = newServers.first {
                        selectedServerID = first.id
                    }
                    showAddServer = false
                }
            )
            .navigationTitle("Add Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAddServer = false
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 450)
        #endif
    }

    // MARK: - Actions

    private func convertAndConnect(_ config: VLessConfig) async throws {
        NSLog("[ContentView] Connecting to %@:%d (security=%@, sni=%@)",
              config.address, config.port, config.security, config.sni ?? "nil")

        // Any of the IP-based categories being on means we include geoip routing
        let xrayJSON = XrayConfigBuilder.buildJSON(
            from: config,
            smartRoutingCountry: effectiveSmartRoutingCountry,
            smartRoutingCustomDomains: smartRoutingEnabled ? smartRoutingCustomDomains : [],
            bypassTLDWebsites: bypassTLDWebsites,
            bypassDomesticIPs: bypassGovernmentBanking
        )
        NSLog("[ContentView] Xray config length: %d", xrayJSON.count)
        try await vpnManager.connect(xrayJSON: xrayJSON)
    }

    /// Reconnect with updated smart routing config if VPN is currently connected.
    private func reconnectIfNeeded() {
        guard vpnManager.status == .connected, let server = selectedServer else { return }
        Task {
            // disconnect() now waits until status actually reaches .disconnected
            await vpnManager.disconnect()
            try? await convertAndConnect(server.vlessConfig)
        }
    }

    private func performInitialLoad() {
        servers = ConfigStore.loadServers()
        selectedServerID = ConfigStore.loadSelectedServerID()

        Task {
            await loadCloudServers()
            await detectCountry()

            // Connect on Launch: auto-connect if enabled and we have a saved server
            if UserDefaults.standard.bool(forKey: "connectOnLaunch"),
               let server = servers.first(where: { $0.id == selectedServerID }),
               vpnManager.status == .disconnected {
                try? await convertAndConnect(server.vlessConfig)
            }
        }
    }

    private func detectCountry() async {
        do {
            let geo = try await IPGeolocationService.fetchCurrentIP()
            if let code = geo.countryCode {
                detectedCountryCode = code
            }
        } catch {
            NSLog("[ContentView] Failed to detect country: %@", error.localizedDescription)
        }
    }

    private func loadCloudServers() async {
        isLoadingCloud = true
        cloudError = nil

        do {
            cloudServers = try await SupabaseServerService.fetchServers()
            refreshCachedCloudServers()
        } catch {
            cloudError = error.localizedDescription
        }

        isLoadingCloud = false
    }

    /// Full sync of cached cloud servers with Supabase:
    /// - Updates existing servers (re-parses VLESS URI + metadata)
    /// - Removes servers no longer in Supabase
    /// - Adds new servers from Supabase
    private func refreshCachedCloudServers() {
        guard !cloudServers.isEmpty else { return }

        let previousSelectedID = selectedServerID
        var newServers = servers.filter { $0.source == .manual }

        for cloud in cloudServers {
            guard let vlessConfig = Self.parseVLessURI(from: cloud) else {
                NSLog("[ContentView] Skipping server '%@': failed to parse VLESS URI", cloud.name)
                continue
            }

            let config = ServerConfig(
                vlessConfig: vlessConfig,
                source: .cloud,
                name: cloud.name,
                supabaseID: cloud.id,
                country: cloud.country,
                countryCode: cloud.countryCode,
                city: cloud.city,
                loadPercentage: cloud.loadPercentage,
                isPremium: cloud.isPremium,
                latencyMs: cloud.latencyMs,
                speedMbps: cloud.speedMbps
            )
            newServers.append(config)
        }

        servers = newServers

        // Restore selection: match by supabaseID, IP address, or pick first available
        if let prevID = previousSelectedID {
            if servers.contains(where: { $0.id == prevID }) {
                // Exact ID match (manual servers or unlikely same UUID)
                selectedServerID = prevID
            } else {
                // Old server got a new VLessConfig ID after re-parse — match by supabaseID or IP
                let oldServer = ConfigStore.loadServers().first { $0.id == prevID }
                let refreshed: ServerConfig? = {
                    if let sid = oldServer?.supabaseID {
                        return servers.first { $0.supabaseID == sid }
                    }
                    if let addr = oldServer?.vlessConfig.address {
                        return servers.first { $0.vlessConfig.address == addr }
                    }
                    return nil
                }()

                if let refreshed {
                    selectedServerID = refreshed.id
                    NSLog("[ContentView] Restored selection to refreshed server: %@", refreshed.name ?? refreshed.vlessConfig.address)
                } else {
                    selectedServerID = servers.first(where: { $0.isPremium != true })?.id ?? servers.first?.id
                    NSLog("[ContentView] Previously selected server removed, auto-selected: %@",
                          selectedServerID?.uuidString ?? "none")
                }
            }
        }

        NSLog("[ContentView] Synced servers: %d cloud + %d manual",
              servers.filter({ $0.source == .cloud }).count,
              servers.filter({ $0.source == .manual }).count)
    }

    /// Extracts and parses a VLessConfig from a SupabaseServer's config_data.
    private static func parseVLessURI(from server: SupabaseServer) -> VLessConfig? {
        guard let configData = server.configData, !configData.isEmpty else { return nil }

        let rawURI: String
        let trimmed = configData.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("vless://") {
            rawURI = trimmed
        } else if let decoded = Data(base64Encoded: trimmed),
                  let decodedString = String(data: decoded, encoding: .utf8),
                  let vlessLine = decodedString.components(separatedBy: .newlines)
                    .first(where: { $0.lowercased().hasPrefix("vless://") }) {
            rawURI = vlessLine.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            return nil
        }

        return try? VLessParser.parse(rawURI)
    }

    private func openSupportEmail() {
        let currentAccountId = accountManager.account?.accountId ?? "unknown"
        let ownerAccountId = rcService.rejectedOwnerAccountId ?? "unknown"
        let subject = "Subscription Transfer Request"
        let body = """
        Hi Doppler VPN Support,

        I need help with a subscription issue.

        My current account ID: \(currentAccountId)
        Subscription owner account ID: \(ownerAccountId)

        Please help me resolve this subscription conflict.

        Thank you.
        """

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:support@simnetiq.store?subject=\(encodedSubject)&body=\(encodedBody)") {
            #if os(iOS)
            UIApplication.shared.open(url)
            #elseif os(macOS)
            NSWorkspace.shared.open(url)
            #endif
        }
    }

    private func selectCloudServer(_ supabaseServer: SupabaseServer) {
        if supabaseServer.isPremium == true && !isEffectivelyPro {
            showPaywall = true
            return
        }

        guard let vlessConfig = Self.parseVLessURI(from: supabaseServer) else {
            NSLog("[ContentView] Failed to parse config for '%@'", supabaseServer.name)
            vpnManager.errorMessage = "Invalid or missing config for '\(supabaseServer.name)'."
            return
        }

        NSLog("[ContentView] Parsed cloud server '%@': address=%@, port=%d, security=%@",
              supabaseServer.name, vlessConfig.address, vlessConfig.port, vlessConfig.security)

        let newConfig = ServerConfig(
            vlessConfig: vlessConfig,
            source: .cloud,
            name: supabaseServer.name,
            supabaseID: supabaseServer.id,
            country: supabaseServer.country,
            countryCode: supabaseServer.countryCode,
            city: supabaseServer.city,
            loadPercentage: supabaseServer.loadPercentage,
            isPremium: supabaseServer.isPremium,
            latencyMs: supabaseServer.latencyMs,
            speedMbps: supabaseServer.speedMbps
        )

        // Replace existing cloud entry for this Supabase server, or append new
        if let index = servers.firstIndex(where: { $0.source == .cloud && ($0.supabaseID == supabaseServer.id || $0.vlessConfig.address == vlessConfig.address) }) {
            servers[index] = newConfig
        } else {
            servers.append(newConfig)
        }

        selectedServerID = newConfig.id
    }
}

// MARK: - App Tab

enum AppTab: String, CaseIterable {
    case vpn
    case smartRoute
    case profile

    var title: String {
        switch self {
        case .vpn: "VPN"
        case .smartRoute: "Smart Route"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .vpn: "shield.fill"
        case .smartRoute: "arrow.triangle.branch"
        case .profile: "person.circle"
        }
    }
}

// MARK: - Previews

#Preview("iPhone") {
    ContentView(vpnManager: VPNManager(), accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService(), languageManager: LanguageManager.shared)
}

#Preview("iPhone Dark") {
    ContentView(vpnManager: VPNManager(), accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService(), languageManager: LanguageManager.shared)
        .preferredColorScheme(.dark)
}

#Preview("iPad / macOS") {
    ContentView(vpnManager: VPNManager(), accountManager: AccountManager(), rcService: RevenueCatService(), syncService: SubscriptionSyncService(), languageManager: LanguageManager.shared)
}
