import SwiftUI

struct ContentView: View {
    let vpnManager: VPNManager
    let accountManager: AccountManager
    let rcService: RevenueCatService

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

    @State private var cloudServers: [SupabaseServer] = []
    @State private var isLoadingCloud = false
    @State private var cloudError: String?
    @State private var showPaywall = false
    @State private var paywallPending = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - Computed Properties

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
        ServerListView(
            servers: $servers,
            selectedServerID: $selectedServerID,
            cloudServers: cloudServers,
            isLoadingCloud: isLoadingCloud,
            cloudError: cloudError,
            isUserPro: rcService.isPro,
            onRefreshCloud: { await loadCloudServers() },
            onSelectCloudServer: { selectCloudServer($0) }
        )
        .navigationTitle("Servers")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(isPresented: $showAddServer) {
            addServerSheet
        }
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
        HomeView(
            vpnManager: vpnManager,
            selectedServer: selectedServer,
            onConnectAndConvert: convertAndConnect,
            smartRoutingEnabled: $smartRoutingEnabled,
            smartRoutingCountry: effectiveSmartRoutingCountry
        )
        #if os(iOS)
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(rcService: rcService, isPresented: $showPaywall)
        }
        #else
        .sheet(isPresented: $showPaywall) {
            PaywallView(rcService: rcService, isPresented: $showPaywall)
        }
        #endif
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
                            .tint(Design.Colors.accent)
                            .accessibilityLabel("Add Server")
                        }
                    }
                    .sheet(isPresented: $showServerList) {
                        serverListSheet
                    }
                    .sheet(isPresented: $showAddServer) {
                        addServerSheet
                    }
                    .fullScreenCover(isPresented: $showPaywall) {
                        PaywallView(rcService: rcService, isPresented: $showPaywall)
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
                        customDomains: $smartRoutingCustomDomains
                    )
                    .navigationTitle("Doppler VPN")
                    .navigationBarTitleDisplayMode(.large)
                }
            }

            Tab("Profile", systemImage: "person.circle", value: .profile) {
                NavigationStack {
                    ProfileView(accountManager: accountManager, rcService: rcService, vpnManager: vpnManager)
                }
            }
        }
        .tint(Design.Colors.accent)
        .onChange(of: servers) {
            ConfigStore.saveServers(servers)
        }
        .onChange(of: selectedServerID) {
            ConfigStore.saveSelectedServerID(selectedServerID)
        }
        .onChange(of: smartRoutingEnabled) {
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
                isUserPro: rcService.isPro,
                onRefreshCloud: { await loadCloudServers() },
                onSelectCloudServer: { server in
                    if server.isPremium == true && !rcService.isPro {
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
        let xrayJSON = XrayConfigBuilder.buildJSON(
            from: config,
            smartRoutingCountry: effectiveSmartRoutingCountry,
            smartRoutingCustomDomains: smartRoutingEnabled ? smartRoutingCustomDomains : []
        )
        try await vpnManager.connect(xrayJSON: xrayJSON)
    }

    /// Reconnect with updated smart routing config if VPN is currently connected.
    private func reconnectIfNeeded() {
        guard vpnManager.status == .connected, let server = selectedServer else { return }
        vpnManager.disconnect()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
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
        } catch {
            cloudError = error.localizedDescription
        }

        isLoadingCloud = false
    }

    private func selectCloudServer(_ supabaseServer: SupabaseServer) {
        if supabaseServer.isPremium == true && !rcService.isPro {
            showPaywall = true
            return
        }

        guard let configData = supabaseServer.configData, !configData.isEmpty else {
            NSLog("[ContentView] Server '%@' has no config_data", supabaseServer.name)
            vpnManager.errorMessage = "Server '\(supabaseServer.name)' has no configuration data."
            return
        }

        // Resolve the raw VLESS URI — handle both raw and base64-encoded formats
        let rawURI: String
        if configData.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("vless://") {
            rawURI = configData.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let decoded = Data(base64Encoded: configData.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decodedString = String(data: decoded, encoding: .utf8) {
            // Marzban subscriptions may contain multiple URIs separated by newlines — take the first VLESS one
            let lines = decodedString.components(separatedBy: .newlines)
            if let vlessLine = lines.first(where: { $0.lowercased().hasPrefix("vless://") }) {
                rawURI = vlessLine.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                NSLog("[ContentView] Base64 decoded but no vless:// URI found for '%@': %@", supabaseServer.name, decodedString.prefix(200).description)
                vpnManager.errorMessage = "No VLESS config found for '\(supabaseServer.name)'."
                return
            }
        } else {
            NSLog("[ContentView] Unrecognized config format for '%@': %@", supabaseServer.name, configData.prefix(100).description)
            vpnManager.errorMessage = "Unrecognized config format for '\(supabaseServer.name)'."
            return
        }

        let vlessConfig: VLessConfig
        do {
            vlessConfig = try VLessParser.parse(rawURI)
        } catch {
            NSLog("[ContentView] Failed to parse VLESS URI for '%@': %@", supabaseServer.name, error.localizedDescription)
            vpnManager.errorMessage = "Invalid config for '\(supabaseServer.name)': \(error.localizedDescription)"
            return
        }

        NSLog("[ContentView] Parsed cloud server '%@': address=%@, port=%d, security=%@",
              supabaseServer.name, vlessConfig.address, vlessConfig.port, vlessConfig.security)

        let newConfig = ServerConfig(
            vlessConfig: vlessConfig,
            source: .cloud,
            country: supabaseServer.country,
            countryCode: supabaseServer.countryCode,
            city: supabaseServer.city,
            loadPercentage: supabaseServer.loadPercentage,
            isPremium: supabaseServer.isPremium,
            latencyMs: supabaseServer.latencyMs,
            speedMbps: supabaseServer.speedMbps
        )

        // Replace existing cloud entry for this Supabase server, or append new
        if let index = servers.firstIndex(where: { $0.source == .cloud && $0.vlessConfig.address == vlessConfig.address }) {
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
}

// MARK: - Previews

#Preview("iPhone") {
    ContentView(vpnManager: VPNManager(), accountManager: AccountManager(), rcService: RevenueCatService())
}

#Preview("iPhone Dark") {
    ContentView(vpnManager: VPNManager(), accountManager: AccountManager(), rcService: RevenueCatService())
        .preferredColorScheme(.dark)
}

#Preview("iPad / macOS") {
    ContentView(vpnManager: VPNManager(), accountManager: AccountManager(), rcService: RevenueCatService())
}
