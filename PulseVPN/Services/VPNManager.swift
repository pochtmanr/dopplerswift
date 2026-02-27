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

    private static let tunnelBundleID = "com.pulsingroutes.vpn.tunnel"
    private static let tunnelDescription = "Pulse Route VPN"
    private static let serverAddress = "PulseRoute"

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
        errorMessage = nil

        // Also save to App Group as backup
        ConfigStore.saveXrayConfig(xrayJSON)

        // Pass config directly via providerConfiguration — no App Group dependency
        if manager == nil {
            try await installManager(xrayJSON: xrayJSON)
        } else {
            try await updateManagerConfig(xrayJSON: xrayJSON)
        }

        guard let manager else {
            throw VPNError.managerNotAvailable
        }

        try manager.connection.startVPNTunnel()
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
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
            errorMessage = "Failed to update kill switch: \(error.localizedDescription)"
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
        case .connecting, .reasserting:
            status = .connecting
        case .disconnecting:
            status = .disconnecting
        case .disconnected:
            status = .disconnected
        case .invalid:
            status = .failed
            errorMessage = "VPN configuration is invalid."
        @unknown default:
            status = .disconnected
        }
    }
}

extension VPNManager {
    enum VPNError: LocalizedError {
        case managerNotAvailable
        var errorDescription: String? { "VPN manager is not available. Please try again." }
    }
}
