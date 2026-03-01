import SwiftUI

// MARK: - Server List View

struct ServerListView: View {
    @Binding var servers: [ServerConfig]
    @Binding var selectedServerID: UUID?

    var cloudServers: [SupabaseServer] = []
    var isLoadingCloud: Bool = false
    var cloudError: String?
    var isUserPro: Bool = false
    var onRefreshCloud: (() async -> Void)?
    var onSelectCloudServer: ((SupabaseServer) -> Void)?

    @State private var searchText = ""

    // MARK: - Filtered Lists

    private var filteredManualServers: [ServerConfig] {
        let manualOnly = servers.filter { $0.source == .manual }
        guard !searchText.isEmpty else { return manualOnly }
        return manualOnly.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredCloudServers: [SupabaseServer] {
        guard !searchText.isEmpty else { return cloudServers }
        return cloudServers.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.locationDisplay.localizedCaseInsensitiveContains(searchText) ||
            $0.country.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasAnyContent: Bool {
        !servers.isEmpty || !cloudServers.isEmpty || isLoadingCloud
    }

    // MARK: - Body

    var body: some View {
        Group {
            if hasAnyContent {
                serverList
            } else {
                emptyState
            }
        }
        .searchable(text: $searchText, prompt: "Search servers")
    }

    // MARK: - Server List

    @ViewBuilder
    private var serverList: some View {
        List {
            if !cloudServers.isEmpty || isLoadingCloud {
                cloudSection
            }

            if !filteredManualServers.isEmpty {
                manualSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .refreshable {
            await onRefreshCloud?()
        }
    }

    // MARK: - Cloud Servers Section

    @ViewBuilder
    private var cloudSection: some View {
        Section {
            if isLoadingCloud {
                loadingRow
            } else if let error = cloudError {
                cloudErrorRow(error)
            } else {
                ForEach(filteredCloudServers) { server in
                    cloudServerRow(server)
                }
            }
        } header: {
            HStack {
                Label("Available Servers", systemImage: "cloud.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                if !isLoadingCloud && cloudError == nil {
                    Text("\(filteredCloudServers.count)")
                        .font(.system(.caption2, design: .monospaced, weight: .medium))
                        .foregroundStyle(Design.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - Manual Servers Section

    @ViewBuilder
    private var manualSection: some View {
        Section {
            ForEach(filteredManualServers) { server in
                manualServerRow(server)
            }
            .onDelete(perform: deleteManualServers)
        } header: {
            HStack {
                Label("Custom Servers", systemImage: "server.rack")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Text("\(filteredManualServers.count)")
                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                    .foregroundStyle(Design.Colors.textTertiary)
            }
        }
    }

    // MARK: - Cloud Server Row

    private func isCloudServerSelected(_ server: SupabaseServer) -> Bool {
        // Match by IP address (stable) rather than display name (VLESS remark may differ from Supabase name)
        let matchingConfig = servers.first { $0.source == .cloud && $0.vlessConfig.address == server.ipAddress }
            ?? servers.first { $0.source == .cloud && $0.displayName == server.name }
        return matchingConfig?.id == selectedServerID && selectedServerID != nil
    }

    @ViewBuilder
    private func cloudServerRow(_ server: SupabaseServer) -> some View {
        let selected = isCloudServerSelected(server)

        Button {
            onSelectCloudServer?(server)
        } label: {
            cloudServerRowContent(server, isSelected: selected)
        }
        .accessibilityLabel("\(server.name), \(server.locationDisplay)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func cloudServerRowContent(_ server: SupabaseServer, isSelected: Bool) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Text(server.flagEmoji)
                .font(.system(size: 24))
                .frame(width: Design.Size.flagSize)

            cloudServerInfo(server, isSelected: isSelected)

            Spacer()

            cloudServerTrailing(server, isSelected: isSelected)
        }
        .padding(.vertical, Design.Spacing.xs)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cloudServerInfo(_ server: SupabaseServer, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Design.Spacing.sm) {
                Text(server.name)
                    .font(.system(.body, design: .rounded, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

                if server.isPremium == true {
                    premiumBadge
                }
            }

            Text(server.locationDisplay)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
        }
    }

    @ViewBuilder
    private func cloudServerTrailing(_ server: SupabaseServer, isSelected: Bool) -> some View {
        if let load = server.loadPercentage {
            loadIndicator(load)
        }

        if let latency = server.latencyMs {
            latencyText(latency)
        }

        if server.isPremium == true && !isUserPro {
            Image(systemName: "lock.fill")
                .foregroundStyle(Design.Colors.premium)
                .font(.caption)
        } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Design.Colors.teal)
                .font(.body)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Manual Server Row

    @ViewBuilder
    private func manualServerRow(_ server: ServerConfig) -> some View {
        let selected = server.id == selectedServerID

        Button {
            withAnimation(Design.Animation.springQuick) {
                selectedServerID = server.id
            }
        } label: {
            HStack(spacing: Design.Spacing.md) {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(Design.Colors.teal)
                    .frame(width: Design.Size.flagSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName)
                        .font(.system(.body, design: .rounded, weight: selected ? .bold : .medium))
                        .foregroundStyle(Design.Colors.textPrimary)

                    HStack(spacing: Design.Spacing.xs) {
                        Text(server.subtitle)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Design.Colors.textSecondary)

                        if server.vlessConfig.security != "none" {
                            securityBadge(server.vlessConfig.security)
                        }
                    }
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Design.Colors.teal)
                        .font(.body)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, Design.Spacing.xs)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(server.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Support Views

    @ViewBuilder
    private var loadingRow: some View {
        HStack(spacing: Design.Spacing.md) {
            ProgressView()
                .tint(Design.Colors.teal)

            Text("Loading servers...")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.vertical, Design.Spacing.sm)
    }

    @ViewBuilder
    private func cloudErrorRow(_ error: String) -> some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Failed to load servers")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(error)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                Task { await onRefreshCloud?() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body)
                    .foregroundStyle(Design.Colors.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Design.Spacing.xs)
    }

    @ViewBuilder
    private var premiumBadge: some View {
        Text("PRO")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(Design.Colors.premium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Design.Colors.premium.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func securityBadge(_ security: String) -> some View {
        let label: String = switch security.lowercased() {
        case "reality", "tls": "ENCRYPTED"
        case "none": "OPEN"
        default: "SECURE"
        }
        Text(label)
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(Design.Colors.teal)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Design.Colors.teal.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func loadIndicator(_ percentage: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(loadColor(percentage))
                .frame(width: 6, height: 6)

            Text("\(percentage)%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Design.Colors.textTertiary)
        }
    }

    @ViewBuilder
    private func latencyText(_ ms: Int) -> some View {
        Text("\(ms)ms")
            .font(.system(.caption2, design: .monospaced, weight: .medium))
            .foregroundStyle(Design.Colors.textTertiary)
    }

    private func loadColor(_ percentage: Int) -> Color {
        switch percentage {
        case 0..<30: return .green
        case 30..<60: return .yellow
        case 60..<80: return .orange
        default: return .red
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Servers", systemImage: "server.rack")
                .foregroundStyle(Design.Colors.textSecondary)
        } description: {
            Text("Add a server manually or pull down to refresh cloud servers.")
                .foregroundStyle(Design.Colors.textTertiary)
        }
    }

    // MARK: - Actions

    private func deleteManualServers(at offsets: IndexSet) {
        let manualOnly = servers.filter { $0.source == .manual }
        let idsToDelete = offsets.map { manualOnly[$0].id }

        if let selectedServerID, idsToDelete.contains(selectedServerID) {
            self.selectedServerID = nil
        }

        servers.removeAll { idsToDelete.contains($0.id) }
    }
}

// MARK: - Previews

#Preview("With Servers") {
    @Previewable @State var selectedID: UUID? = nil
    @Previewable @State var servers: [ServerConfig] = {
        let configs = [
            VLessConfig(
                id: UUID(), address: "de1.example.com", port: 443, uuid: "a",
                flow: nil, security: "reality", sni: "example.com",
                publicKey: nil, shortId: nil, fingerprint: nil,
                network: "tcp", path: nil, serviceName: nil,
                remark: "Germany #1", rawURI: "vless://a@de1.example.com:443"
            ),
        ]
        return configs.map { ServerConfig(vlessConfig: $0) }
    }()

    let cloudServers: [SupabaseServer] = [
        SupabaseServer(
            id: UUID(), name: "Russia 1", country: "Russia",
            countryCode: "RU", city: "Moscow", ipAddress: "192.0.2.1",
            port: 51820, protocol: "wireguard", configData: nil, loadPercentage: 15,
            isPremium: false, latencyMs: 30, isActive: true, speedMbps: 1000
        ),
        SupabaseServer(
            id: UUID(), name: "UK (London)", country: "United Kingdom",
            countryCode: "GB", city: "London", ipAddress: "198.51.100.1",
            port: 1194, protocol: "udp", configData: nil, loadPercentage: 45,
            isPremium: true, latencyMs: 55, isActive: true, speedMbps: nil
        ),
    ]

    NavigationStack {
        ServerListView(
            servers: $servers,
            selectedServerID: $selectedID,
            cloudServers: cloudServers
        )
        .navigationTitle("Servers")
    }
}

#Preview("Empty") {
    @Previewable @State var selectedID: UUID? = nil
    @Previewable @State var servers: [ServerConfig] = []

    NavigationStack {
        ServerListView(servers: $servers, selectedServerID: $selectedID)
            .navigationTitle("Servers")
    }
}
