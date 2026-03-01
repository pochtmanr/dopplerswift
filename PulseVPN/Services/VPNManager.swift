import Foundation
import NetworkExtension
import Observation

@Observable
final class VPNManager {

    // MARK: - Public Properties

    private(set) var status: ConnectionStatus = .disconnected
    var errorMessage: String?

    // MARK: - Private Properties

    private var manager: NETunnelProviderManager?
    private var statusObserver: Any?
    /// Guards against rapid connect/disconnect race conditions
    private var isPerformingAction = false
    /// Tracks if on-demand was temporarily disabled for disconnect
    private var pendingKillSwitchRestore = false

    private static let tunnelBundleID = "com.simnetiq.vpnreact.tunnel"
    private static let tunnelDescription = "Doppler VPN"
    private static let serverAddress = "Doppler"

    // MARK: - Lifecycle

    init() {
        Task { await loadManager() }
    }

    deinit {
        if let observer = statusObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    func connect(xrayJSON: String) async throws {
        guard !isPerformingAction else {
            NSLog("[VPNManager] connect() blocked — action already in progress")
            return
        }
        // Lock stays held until status transitions (released in updateStatus)
        isPerformingAction = true

        errorMessage = nil

        // Also save to App Group as backup
        ConfigStore.saveXrayConfig(xrayJSON)

        do {
            // Pass config directly via providerConfiguration — no App Group dependency
            if manager == nil {
                try await installManager(xrayJSON: xrayJSON)
            } else {
                try await updateManagerConfig(xrayJSON: xrayJSON)
            }

            guard let manager else {
                isPerformingAction = false
                throw VPNError.managerNotAvailable
            }

            try manager.connection.startVPNTunnel()
            // isPerformingAction is released in updateStatus when status reaches
            // .connected, .disconnected, or .failed
        } catch {
            isPerformingAction = false
            throw error
        }
    }

    func disconnect() async {
        guard !isPerformingAction else {
            NSLog("[VPNManager] disconnect() blocked — action already in progress")
            // If already disconnecting, wait for it to complete
            if status == .disconnecting {
                await waitForDisconnect()
            }
            return
        }
        // Lock stays held until status transitions (released in updateStatus)
        isPerformingAction = true

        guard let manager else {
            isPerformingAction = false
            return
        }

        // If Kill Switch (on-demand) is active, disable it first so the system
        // doesn't immediately reconnect after we stop the tunnel.
        let wasOnDemandEnabled = manager.isOnDemandEnabled
        if wasOnDemandEnabled {
            manager.isOnDemandEnabled = false
            do {
                try await manager.saveToPreferences()
                try await manager.loadFromPreferences()
            } catch {
                NSLog("[VPNManager] Failed to disable on-demand before disconnect: \(error)")
            }
        }

        // Track that we need to restore kill switch after disconnect completes
        if wasOnDemandEnabled && UserDefaults.standard.bool(forKey: "killSwitch") {
            pendingKillSwitchRestore = true
        }

        manager.connection.stopVPNTunnel()

        // Wait for status to actually reach .disconnected so callers
        // (like reconnectIfNeeded) can safely call connect() after this returns
        await waitForDisconnect()
    }

    /// Waits until VPN status reaches a non-active state (disconnected/failed).
    /// Times out after 5 seconds to avoid deadlock.
    private func waitForDisconnect() async {
        let start = Date()
        while status == .connected || status == .connecting || status == .disconnecting {
            try? await Task.sleep(for: .milliseconds(100))
            if Date().timeIntervalSince(start) > 5 { break }
        }
    }

    func setKillSwitch(enabled: Bool) async {
        if manager == nil {
            await loadManager()
        }
        guard let manager else { return }

        if enabled {
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = true
        } else {
            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }

        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
            errorMessage = "Failed to update always-on VPN: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    private func loadManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()

            if let existing = managers.first(where: {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?
                    .providerBundleIdentifier == Self.tunnelBundleID
            }) {
                manager = existing
                observeStatus(existing)
                updateStatus(from: existing.connection.status)
            }
        } catch {
            errorMessage = "Failed to load VPN configuration: \(error.localizedDescription)"
        }
    }

    private func installManager(xrayJSON: String) async throws {
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = Self.tunnelBundleID
        tunnelProtocol.serverAddress = Self.serverAddress
        tunnelProtocol.providerConfiguration = ["xrayJSON": xrayJSON]

        let newManager = NETunnelProviderManager()
        newManager.localizedDescription = Self.tunnelDescription
        newManager.protocolConfiguration = tunnelProtocol
        newManager.isEnabled = true

        // Apply kill switch if enabled
        if UserDefaults.standard.bool(forKey: "killSwitch") {
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            newManager.onDemandRules = [connectRule]
            newManager.isOnDemandEnabled = true
        }

        try await newManager.saveToPreferences()
        try await newManager.loadFromPreferences()

        manager = newManager
        observeStatus(newManager)
    }

    private func updateManagerConfig(xrayJSON: String) async throws {
        guard let manager,
              let proto = manager.protocolConfiguration as? NETunnelProviderProtocol
        else { return }

        proto.providerConfiguration = ["xrayJSON": xrayJSON]
        manager.protocolConfiguration = proto

        // Preserve kill switch setting
        if UserDefaults.standard.bool(forKey: "killSwitch") {
            let connectRule = NEOnDemandRuleConnect()
            connectRule.interfaceTypeMatch = .any
            manager.onDemandRules = [connectRule]
            manager.isOnDemandEnabled = true
        } else {
            manager.onDemandRules = []
            manager.isOnDemandEnabled = false
        }

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    }

    private func observeStatus(_ manager: NETunnelProviderManager) {
        if let existing = statusObserver {
            NotificationCenter.default.removeObserver(existing)
        }

        statusObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: manager.connection,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            updateStatus(from: manager.connection.status)
        }
    }

    private func updateStatus(from vpnStatus: NEVPNStatus) {
        switch vpnStatus {
        case .connected:
            status = .connected
            errorMessage = nil
            isPerformingAction = false
        case .connecting, .reasserting:
            status = .connecting
        case .disconnecting:
            status = .disconnecting
        case .disconnected:
            status = .disconnected
            isPerformingAction = false
            restoreKillSwitchIfNeeded()
        case .invalid:
            status = .failed
            errorMessage = "VPN configuration is invalid."
            isPerformingAction = false
        @unknown default:
            status = .disconnected
            isPerformingAction = false
        }
    }

    /// Re-enables on-demand rules after a user-initiated disconnect.
    /// This ensures Kill Switch is ready for the next connection without
    /// auto-reconnecting immediately after the user pressed disconnect.
    private func restoreKillSwitchIfNeeded() {
        guard pendingKillSwitchRestore else { return }
        pendingKillSwitchRestore = false

        Task {
            await setKillSwitch(enabled: true)
        }
    }
}

extension VPNManager {
    enum VPNError: LocalizedError {
        case managerNotAvailable
        var errorDescription: String? { "VPN manager is not available. Please try again." }
    }
}
