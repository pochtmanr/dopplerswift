import SwiftUI
import MapKit

// MARK: - Home View

struct HomeView: View {
    @Bindable var vpnManager: VPNManager
    let selectedServer: ServerConfig?
    let onConnectAndConvert: (VLessConfig) async throws -> Void
    var onServerTap: (() -> Void)?
    var onSmartRouteTap: (() -> Void)?
    @Binding var smartRoutingEnabled: Bool
    let smartRoutingCountry: String?

    @State private var isProcessing = false
    @State private var connectionDate: Date?
    @State private var timerValue: TimeInterval = 0
    @State private var timer: Timer?
    @State private var userIPGeo: IPGeolocation?
    @State private var serverIPGeo: IPGeolocation?
    @State private var speedTestResult: SpeedTestResult?
    @State private var speedTestRunning = false

    private var isConnected: Bool {
        vpnManager.status == .connected
    }

    private var isTransitioning: Bool {
        vpnManager.status == .connecting || vpnManager.status == .disconnecting
    }

    private var canInteract: Bool {
        selectedServer != nil && !isProcessing && !isTransitioning
    }

    private var statusColor: Color {
        Design.Colors.statusColor(for: vpnManager.status)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: Design.Spacing.md)

                    connectSection

                    Spacer()
                        .frame(height: Design.Spacing.md)

                    serverInfoCard
                        .padding(.horizontal, Design.Spacing.md)

                    mapAndWidgetSection
                        .padding(.horizontal, Design.Spacing.md)
                        .padding(.top, Design.Spacing.sm)
                        .padding(.bottom, Design.Spacing.md)

                    if let errorMessage = vpnManager.errorMessage {
                        errorBanner(errorMessage)
                            .padding(.horizontal, Design.Spacing.md)
                            .padding(.bottom, Design.Spacing.md)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(minHeight: 600)
            }
            .scrollIndicators(.hidden)
        }
        .animation(Design.Animation.springDefault, value: vpnManager.status)
        .animation(Design.Animation.springQuick, value: vpnManager.errorMessage)
        .task { await fetchGeolocation() }
        .onChange(of: selectedServer) { _, _ in
            Task { await fetchServerGeo() }
        }
        .onChange(of: vpnManager.status) { _, newValue in
            handleStatusChange(newValue)
            // Refresh user geo on connect (shows VPN exit location) and disconnect (shows real location)
            if newValue == .connected || newValue == .disconnected {
                Task { await fetchUserGeo(force: true) }
            }
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
                    statusColor.opacity(0.06),
                    Color.clear
                ],
                center: .center,
                startRadius: 50,
                endRadius: 400
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Server Info Card

    @ViewBuilder
    private var serverInfoCard: some View {
        Button {
            onServerTap?()
        } label: {
            serverCardContent
                .padding(Design.Spacing.md)
                .contentShape(Rectangle())
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Design.CornerRadius.lg))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedServer?.displayName ?? "No server selected")
        .accessibilityHint("Double tap to change server")
    }

    @ViewBuilder
    private var serverCardContent: some View {
        if let server = selectedServer {
            selectedServerContent(server)
        } else {
            emptyServerContent
        }
    }

    @ViewBuilder
    private func selectedServerContent(_ server: ServerConfig) -> some View {
        HStack(spacing: Design.Spacing.md) {
            serverFlag(server)

            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)
                    .lineLimit(1)

                Text(server.subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Design.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let latency = server.latencyMs {
                latencyBadge(latency)
            }

            Image(systemName: "chevron.forward")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Design.Colors.teal, in: Circle())
        }
    }

    @ViewBuilder
    private func serverFlag(_ server: ServerConfig) -> some View {
        Text(server.flagEmoji.isEmpty ? "" : server.flagEmoji)
            .font(.system(size: 28))
            .frame(width: Design.Size.flagSize, height: Design.Size.flagSize)
            .overlay {
                if server.flagEmoji.isEmpty {
                    Image(systemName: "globe")
                        .font(.title2)
                        .foregroundStyle(Design.Colors.teal)
                }
            }
    }

    @ViewBuilder
    private var emptyServerContent: some View {
        HStack(spacing: Design.Spacing.md) {
            Image(systemName: "globe")
                .font(.title2)
                .foregroundStyle(Design.Colors.textTertiary)
                .frame(width: Design.Size.flagSize, height: Design.Size.flagSize)

            Text("Select a Server")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.system(.caption2, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Design.Colors.teal, in: Circle())
        }
    }

    // MARK: - Connect Section

    @ViewBuilder
    private var connectSection: some View {
        VStack(spacing: Design.Spacing.sm) {
            ZStack {
                ConnectionStatusView(status: vpnManager.status)

                Button {
                    handleButtonTap()
                } label: {
                    Circle()
                        .fill(.clear)
                        .frame(
                            width: Design.Size.connectButtonDiameter,
                            height: Design.Size.connectButtonDiameter
                        )
                        .glassEffect(
                            .regular.tint(statusColor.opacity(0.15)),
                            in: .circle
                        )
                        .overlay {
                            buttonContent
                        }
                        .shadow(color: statusColor.opacity(0.2), radius: 16, y: 6)
                }
                .buttonStyle(ConnectButtonStyle())
                .disabled(isProcessing || isTransitioning)
                .accessibilityLabel(selectedServer == nil ? "Select a server" : buttonAccessibilityLabel)
                .accessibilityHint(selectedServer == nil ? "Double tap to choose a server" : "")
                #if os(iOS)
                .sensoryFeedback(.impact(weight: .medium), trigger: vpnManager.status)
                #endif
            }

            // Labels below the button
            buttonLabel
        }
    }

    // MARK: - Button Content (icon only)

    @ViewBuilder
    private var buttonContent: some View {
        switch vpnManager.status {
        case .connecting, .disconnecting:
            ProgressView()
                .tint(.white)
                .controlSize(.large)

        case .connected:
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))

        default:
            Image(systemName: buttonIcon)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    // MARK: - Button Label (text below)

    @ViewBuilder
    private var buttonLabel: some View {
        switch vpnManager.status {
        case .connecting:
            Text("Connecting...")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(statusColor)

        case .disconnecting:
            Text("Disconnecting...")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(statusColor)

        case .connected:
            VStack(spacing: 2) {
                Text("Connected")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.connected)

                Text("tap to disconnect")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }

        case .disconnected:
            Text("Connect")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

        case .failed:
            Text("Retry")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        VStack(spacing: Design.Spacing.sm) {
            if !isConnected {
                Text(vpnManager.status.displayText)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(statusColor)
                    .contentTransition(.numericText())
            }

            if isConnected {
                timerPill
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(Design.Animation.springDefault, value: isConnected)
    }

    // MARK: - Timer Pill

    @ViewBuilder
    private var timerPill: some View {
        HStack(spacing: Design.Spacing.sm) {
            Circle()
                .fill(Design.Colors.connected)
                .frame(width: 6, height: 6)

            Text(formattedTime)
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Design.Spacing.md)
        .padding(.vertical, Design.Spacing.sm)
        .glassEffect(.regular, in: .capsule)
    }

    private var formattedTime: String {
        let hours = Int(timerValue) / 3600
        let minutes = (Int(timerValue) % 3600) / 60
        let seconds = Int(timerValue) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Latency Badge

    @ViewBuilder
    private func latencyBadge(_ ms: Int) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(latencyColor(ms))
                .frame(width: 6, height: 6)

            Text("\(ms) ms")
                .font(.system(.caption2, design: .monospaced, weight: .medium))
                .foregroundStyle(Design.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Design.Colors.surfaceCardHover, in: Capsule())
    }

    private func latencyColor(_ ms: Int) -> Color {
        switch ms {
        case 0..<50: return .green
        case 50..<100: return .yellow
        case 100..<200: return .orange
        default: return .red
        }
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Design.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Design.Colors.textSecondary)
                .lineLimit(2)

            Spacer()

            Button {
                withAnimation {
                    vpnManager.errorMessage = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(Design.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Design.Spacing.md)
        .glassEffect(.regular.tint(.red), in: .rect(cornerRadius: Design.CornerRadius.md))
    }

    // MARK: - Map + Widget Section

    @ViewBuilder
    private var mapAndWidgetSection: some View {
        let active = smartRoutingEnabled && isConnected && smartRoutingCountry != nil

        VStack(spacing: Design.Spacing.sm) {
            // Row 1: Smart Route + Map side by side (1:1 each)
            HStack(spacing: Design.Spacing.sm) {
                smartRouteCard(active: active)
                    .aspectRatio(1.0, contentMode: .fit)

                MapCardView(
                    userGeo: userIPGeo,
                    serverGeo: serverIPGeo,
                    isConnected: isConnected,
                    isExpanded: false
                )
                .aspectRatio(1.0, contentMode: .fit)
            }

            // Row 2: Speed Test (full width)
            SpeedTestWidget(
                compact: false,
                result: $speedTestResult,
                isRunning: $speedTestRunning
            )
            .frame(height: 64)
        }
    }

    // MARK: - Smart Route Card

    @ViewBuilder
    private func smartRouteCard(active: Bool) -> some View {
        VStack(spacing: Design.Spacing.sm) {
            Spacer(minLength: 0)

            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(smartRoutingEnabled ? Design.Colors.teal : Design.Colors.textTertiary)

            VStack(spacing: 2) {
                Text("Smart Route")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Design.Colors.textPrimary)

                Text(active ? "Active" : smartRoutingEnabled ? "VPN Off" : "Off")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(active ? Design.Colors.teal : Design.Colors.textSecondary)
            }
            .onTapGesture { onSmartRouteTap?() }

            Spacer(minLength: 0)

            Button {
                smartRoutingEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: smartRoutingEnabled ? "xmark" : "power")
                        .font(.system(size: 10, weight: .bold))

                    Text(smartRoutingEnabled ? "Turn Off" : "Turn On")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(smartRoutingEnabled ? Design.Colors.textPrimary : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Design.Spacing.sm)
                .background(
                    smartRoutingEnabled ? Color.clear : Design.Colors.teal,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(smartRoutingEnabled ? Design.Colors.textTertiary.opacity(0.3) : Color.clear, lineWidth: 1)
                )
            }
            .buttonStyle(ConnectButtonStyle())
        }
        .multilineTextAlignment(.center)
        .padding(Design.Spacing.md)
        .glassEffect(
            active ? .regular.tint(Design.Colors.teal.opacity(0.15)) : .regular,
            in: .rect(cornerRadius: Design.CornerRadius.lg)
        )
    }

    // MARK: - Button Properties

    private var buttonGradientColors: [Color] {
        switch vpnManager.status {
        case .connected:
            return [Color.green.opacity(0.9), Color.green.opacity(0.7)]
        case .connecting, .disconnecting:
            return [Color.orange.opacity(0.7), Color.orange.opacity(0.5)]
        case .disconnected:
            return [Design.Colors.teal, Design.Colors.teal.opacity(0.7)]
        case .failed:
            return [Design.Colors.teal, Design.Colors.teal.opacity(0.7)]
        }
    }

    private var buttonIcon: String {
        switch vpnManager.status {
        case .connected: "stop.fill"
        case .connecting, .disconnecting: "ellipsis"
        case .disconnected: "power"
        case .failed: "arrow.clockwise"
        }
    }

    private var buttonAccessibilityLabel: String {
        switch vpnManager.status {
        case .connected: String(localized: "Disconnect from VPN")
        case .connecting: String(localized: "Connecting to VPN")
        case .disconnecting: String(localized: "Disconnecting from VPN")
        case .disconnected: String(localized: "Connect to VPN")
        case .failed: String(localized: "Retry VPN connection")
        }
    }

    // MARK: - Actions

    private func handleButtonTap() {
        if selectedServer == nil {
            onServerTap?()
            return
        }
        // Extra guard: if already processing or transitioning, ignore tap
        guard !isProcessing, !isTransitioning else { return }

        if isConnected {
            handleDisconnect()
        } else {
            handleConnect()
        }
    }

    private func handleConnect() {
        guard !isProcessing else { return }
        guard let server = selectedServer else {
            NSLog("[HomeView] handleConnect: selectedServer is nil! Cannot connect.")
            vpnManager.errorMessage = String(localized: "No server selected. Please select a server.")
            return
        }
        isProcessing = true
        NSLog("[HomeView] handleConnect: server=%@, address=%@", server.displayName, server.vlessConfig.address)
        Task {
            defer { isProcessing = false }
            do {
                try await onConnectAndConvert(server.vlessConfig)
            } catch {
                NSLog("[HomeView] handleConnect error: %@", error.localizedDescription)
                vpnManager.errorMessage = error.localizedDescription
            }
        }
    }

    private func handleDisconnect() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            defer { isProcessing = false }
            await vpnManager.disconnect()
        }
    }

    // MARK: - Geolocation

    private func fetchGeolocation() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await fetchUserGeo() }
            group.addTask { await fetchServerGeo() }
        }
    }

    @MainActor
    private func fetchUserGeo(force: Bool = false) async {
        if !force, userIPGeo != nil { return }
        do {
            let geo = try await IPGeolocationService.fetchCurrentIP()
            userIPGeo = geo
            NSLog("[HomeView] userGeo: ip=%@, lat=%@, lon=%@, coord=%@",
                  geo.ip,
                  geo.latitude.map { "\($0)" } ?? "nil",
                  geo.longitude.map { "\($0)" } ?? "nil",
                  geo.coordinate != nil ? "OK" : "NIL")
        } catch {
            NSLog("[HomeView] Failed to fetch user IP geo: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func fetchServerGeo() async {
        guard let address = selectedServer?.vlessConfig.address else {
            NSLog("[HomeView] fetchServerGeo: no selectedServer or address, clearing serverIPGeo")
            serverIPGeo = nil
            return
        }
        do {
            let geo = try await IPGeolocationService.fetch(for: address)
            serverIPGeo = geo
            NSLog("[HomeView] serverGeo: address=%@, ip=%@, lat=%@, lon=%@, coord=%@",
                  address,
                  geo.ip,
                  geo.latitude.map { "\($0)" } ?? "nil",
                  geo.longitude.map { "\($0)" } ?? "nil",
                  geo.coordinate != nil ? "OK" : "NIL")
        } catch {
            NSLog("[HomeView] Failed to fetch server IP geo for %@: %@", address, error.localizedDescription)
        }
    }

    // MARK: - Timer Management

    private func handleStatusChange(_ newStatus: ConnectionStatus) {
        if newStatus == .connected {
            connectionDate = Date()
            timerValue = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                if let connectionDate {
                    timerValue = Date().timeIntervalSince(connectionDate)
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
            if newStatus == .disconnected || newStatus == .failed {
                connectionDate = nil
                timerValue = 0
            }
        }
    }
}

// MARK: - Connect Button Style

struct ConnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(Design.Animation.springQuick, value: configuration.isPressed)
    }
}
