import NetworkExtension
import LibXray
import Network

final class PacketTunnelProvider: NEPacketTunnelProvider {

    /// Monitors network path changes to detect connectivity loss
    private var pathMonitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "com.simnetiq.vpnreact.tunnel.pathmonitor")

    /// Xray startup timeout in seconds (Apple kills extensions after ~60s)
    private static let xrayStartTimeout: TimeInterval = 15

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        TunnelLogger.clear()
        TunnelLogger.log("=== START TUNNEL ===")

        // 1. Get config
        let configJSON: String
        if let proto = protocolConfiguration as? NETunnelProviderProtocol,
           let json = proto.providerConfiguration?["xrayJSON"] as? String {
            configJSON = json
            TunnelLogger.log("Config from providerConfiguration (\(json.count) bytes)")
        } else if let json = ConfigStore.loadXrayConfig() {
            configJSON = json
            TunnelLogger.log("Config from App Group (\(json.count) bytes)")
        } else {
            TunnelLogger.log("FAIL: No config found in providerConfiguration or App Group")
            completionHandler(TunnelError.noConfiguration)
            return
        }

        // 2. Prepare Xray config with SOCKS + HTTP inbounds
        let preparedConfig = prepareXrayConfig(configJSON)
        let (socksPort, httpPort) = extractProxyPorts(preparedConfig)
        TunnelLogger.log("Ports: SOCKS=\(socksPort) HTTP=\(httpPort)")

        // Log the full prepared config for debugging
        TunnelLogger.log("--- PREPARED CONFIG START ---")
        TunnelLogger.log(preparedConfig)
        TunnelLogger.log("--- PREPARED CONFIG END ---")

        // 2b. Extract server IP to exclude from tunnel routes (prevents routing loop)
        let serverAddress = extractServerAddress(preparedConfig)
        TunnelLogger.log("Extracted server address: \(serverAddress ?? "NONE")")

        Task {
            do {
                // 3. Create directories
                let sharedDir = getSharedDirectory()
                let workingDir = getWorkingDirectory()
                let cacheDir = getCacheDirectory()

                TunnelLogger.log("sharedDir: \(sharedDir.path)")

                try FileManager.default.createDirectory(
                    at: sharedDir, withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: workingDir, withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: cacheDir, withIntermediateDirectories: true
                )
                TunnelLogger.log("Directories created")

                // 3b. Resolve server IP (may be a hostname)
                let serverIP = await resolveServerIP(serverAddress)
                TunnelLogger.log("Resolved server IP: \(serverIP ?? "NONE")")

                // 4. Apply network settings
                try await applyNetworkSettings(socksPort: socksPort, httpPort: httpPort, serverIP: serverIP)
                TunnelLogger.log("Network settings applied")

                // 5. Start Xray
                let datDir = sharedDir.path
                // mph cache disabled — our routing uses domain: (TLD matching)
                // and geoip: rules, neither of which need geosite mph cache.
                // Remove stale cache file if present to prevent EOF errors.
                let staleCache = cacheDir.appendingPathComponent("geosite.mph")
                try? FileManager.default.removeItem(at: staleCache)
                let mphCachePath = ""

                TunnelLogger.log("datDir: \(datDir)")
                TunnelLogger.log("mphCachePath: \(mphCachePath)")

                let fm = FileManager.default

                // Check if geoip/geosite files exist in datDir
                let geoipPath = sharedDir.appendingPathComponent("geoip.dat").path
                let geositePath = sharedDir.appendingPathComponent("geosite.dat").path
                TunnelLogger.log("geoip.dat exists at datDir: \(fm.fileExists(atPath: geoipPath))")
                TunnelLogger.log("geosite.dat exists at datDir: \(fm.fileExists(atPath: geositePath))")

                // Also check bundle
                if let bundleGeoip = Bundle.main.path(forResource: "geoip", ofType: "dat") {
                    TunnelLogger.log("geoip.dat in bundle: \(bundleGeoip)")
                    // Copy to datDir if not there
                    if !fm.fileExists(atPath: geoipPath) {
                        try fm.copyItem(atPath: bundleGeoip, toPath: geoipPath)
                        TunnelLogger.log("Copied geoip.dat to datDir")
                    }
                } else {
                    TunnelLogger.log("geoip.dat NOT in bundle")
                }
                if let bundleGeosite = Bundle.main.path(forResource: "geosite", ofType: "dat") {
                    TunnelLogger.log("geosite.dat in bundle: \(bundleGeosite)")
                    if !fm.fileExists(atPath: geositePath) {
                        try fm.copyItem(atPath: bundleGeosite, toPath: geositePath)
                        TunnelLogger.log("Copied geosite.dat to datDir")
                    }
                } else {
                    TunnelLogger.log("geosite.dat NOT in bundle")
                }

                // Log Xray version
                if let versionResponse = decodeCallResponse(LibXrayXrayVersion()),
                   let version = versionResponse.data {
                    TunnelLogger.log("Xray version: \(version)")
                } else {
                    TunnelLogger.log("Could not get Xray version")
                }

                // Create request
                var requestError: NSError?
                let request = LibXrayNewXrayRunFromJSONRequest(
                    datDir,
                    mphCachePath,
                    preparedConfig,
                    &requestError
                )
                if let requestError {
                    TunnelLogger.log("FAIL creating request: \(requestError.localizedDescription)")
                    completionHandler(requestError)
                    return
                }
                TunnelLogger.log("Xray request created, calling RunXrayFromJSON...")

                // Run Xray with timeout watchdog — if LibXray blocks for too long,
                // Apple will kill the extension anyway (~60s). We fail fast at 15s
                // so the user sees a clear error instead of a silent timeout.
                let xrayResult: String? = await withCheckedContinuation { continuation in
                    let completed = LockedFlag()

                    // Timeout watchdog
                    DispatchQueue.global().asyncAfter(deadline: .now() + Self.xrayStartTimeout) {
                        if completed.setIfFirst() {
                            TunnelLogger.log("FAIL: Xray startup timed out after \(Self.xrayStartTimeout)s")
                            continuation.resume(returning: nil)
                        }
                    }

                    // Actual Xray startup (may block)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = LibXrayRunXrayFromJSON(request)
                        if completed.setIfFirst() {
                            continuation.resume(returning: result)
                        }
                    }
                }

                guard let responseBase64 = xrayResult else {
                    completionHandler(TunnelError.xrayStartFailed("Startup timed out after \(Int(Self.xrayStartTimeout))s"))
                    return
                }

                TunnelLogger.log("RunXrayFromJSON returned (\(responseBase64.count) chars)")

                guard let response = decodeCallResponse(responseBase64) else {
                    TunnelLogger.log("FAIL: Could not decode response. Raw: \(String(responseBase64.prefix(200)))")
                    completionHandler(TunnelError.xrayStartFailed("Invalid response"))
                    return
                }

                guard response.success else {
                    let message = response.error ?? response.data ?? "unknown error"
                    TunnelLogger.log("FAIL Xray: \(message)")
                    completionHandler(TunnelError.xrayStartFailed(message))
                    return
                }

                TunnelLogger.log("=== CONNECTED SUCCESSFULLY ===")
                self.startNetworkMonitor()
                completionHandler(nil)
            } catch {
                TunnelLogger.log("FAIL exception: \(error.localizedDescription)")
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        TunnelLogger.log("=== STOP (reason: \(reason.rawValue)) ===")

        // Stop network path monitor
        stopNetworkMonitor()

        // Stop Xray core
        if let response = decodeCallResponse(LibXrayStopXray()), !response.success {
            TunnelLogger.log("stopXray error: \(response.error ?? "unknown")")
        }

        TunnelLogger.log("Cleanup complete")
        completionHandler()
    }

    // MARK: - Network Monitoring

    /// Monitors device network path and updates tunnel status on connectivity changes.
    /// When the device loses network, we signal reasserting so the UI reflects the state.
    /// When network returns, we re-apply settings to resume proxy traffic.
    private func startNetworkMonitor() {
        stopNetworkMonitor()

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            switch path.status {
            case .satisfied:
                TunnelLogger.log("Network path: satisfied")
                // Network restored — reassert tunnel settings so proxy resumes
                self.reasserting = false
            case .unsatisfied:
                TunnelLogger.log("Network path: unsatisfied (no connectivity)")
                // Signal to the system that the tunnel is temporarily unavailable
                self.reasserting = true
            case .requiresConnection:
                TunnelLogger.log("Network path: requiresConnection")
                self.reasserting = true
            @unknown default:
                TunnelLogger.log("Network path: unknown status")
            }
        }
        monitor.start(queue: monitorQueue)
        pathMonitor = monitor
        TunnelLogger.log("Network path monitor started")
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - Network Settings

    private func applyNetworkSettings(socksPort: Int, httpPort: Int, serverIP: String?) async throws {
        let tunnelRemote = serverIP ?? "127.0.0.1"
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelRemote)
        settings.mtu = NSNumber(value: 1500)

        // IPv4: assign a tunnel address but do NOT set includedRoutes.
        // Xray doesn't read raw TUN packets — it only listens on HTTP/SOCKS ports.
        // If we set includedRoutes = [default], ALL IP traffic gets captured into
        // the TUN interface where nothing reads it → DNS and non-HTTP traffic dies.
        // Instead, rely purely on the HTTP proxy settings for traffic routing.
        let ipv4 = NEIPv4Settings(
            addresses: ["172.19.0.1"],
            subnetMasks: ["255.255.255.252"]
        )
        ipv4.includedRoutes = []
        settings.ipv4Settings = ipv4

        // DNS: resolved directly (not through tunnel since no TUN capture)
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])

        // HTTP proxy: iOS routes all HTTP/HTTPS traffic through Xray's HTTP inbound
        let proxy = NEProxySettings()
        if httpPort > 0 {
            let server = NEProxyServer(address: "127.0.0.1", port: httpPort)
            proxy.httpServer = server
            proxy.httpsServer = server
            proxy.httpEnabled = true
            proxy.httpsEnabled = true
        }
        // matchDomains = [""] means ALL domains go through the proxy
        proxy.matchDomains = [""]
        settings.proxySettings = proxy

        TunnelLogger.log("Network settings: proxy=127.0.0.1:\(httpPort), DNS=1.1.1.1, no TUN capture")
        try await setTunnelNetworkSettings(settings)
    }

    // MARK: - Server Address Extraction

    private func extractServerAddress(_ config: String) -> String? {
        guard let data = config.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outbounds = root["outbounds"] as? [[String: Any]]
        else { return nil }

        let proxyProtocols: Set<String> = ["vless", "vmess", "trojan", "shadowsocks"]
        for outbound in outbounds {
            guard let proto = outbound["protocol"] as? String,
                  proxyProtocols.contains(proto),
                  let settings = outbound["settings"] as? [String: Any],
                  let vnext = settings["vnext"] as? [[String: Any]],
                  let first = vnext.first,
                  let address = first["address"] as? String
            else { continue }
            return address
        }
        return nil
    }

    private func resolveServerIP(_ address: String?) async -> String? {
        guard let address, !address.isEmpty else { return nil }

        // If already an IPv4 address, return as-is
        var sin = sockaddr_in()
        if address.withCString({ inet_pton(AF_INET, $0, &sin.sin_addr) }) == 1 {
            return address
        }

        // Resolve hostname to IP using getaddrinfo (works in NE context)
        TunnelLogger.log("Resolving hostname: \(address)")
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(address, nil, &hints, &result)
        defer { if result != nil { freeaddrinfo(result) } }

        guard status == 0, let addrInfo = result else {
            TunnelLogger.log("DNS resolution failed for \(address): \(String(cString: gai_strerror(status)))")
            return nil
        }

        if addrInfo.pointee.ai_family == AF_INET {
            let sockAddr = addrInfo.pointee.ai_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0 }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            var addr = sockAddr.pointee.sin_addr
            inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN))
            let ip = String(cString: buf)
            TunnelLogger.log("Resolved \(address) -> \(ip)")
            return ip
        }

        return nil
    }

    // MARK: - Config Preparation

    private func prepareXrayConfig(_ rawConfig: String) -> String {
        guard let data = rawConfig.data(using: .utf8),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return rawConfig }

        var inbounds = (root["inbounds"] as? [[String: Any]]) ?? []

        inbounds = inbounds.filter { ($0["protocol"] as? String)?.lowercased() != "tun" }

        if !inbounds.contains(where: { ($0["protocol"] as? String)?.lowercased() == "socks" }) {
            inbounds.append([
                "tag": "socks",
                "port": 10808,
                "listen": "127.0.0.1",
                "protocol": "socks",
                "settings": ["auth": "noauth", "udp": true]
            ])
        }

        if !inbounds.contains(where: { ($0["protocol"] as? String)?.lowercased() == "http" }) {
            inbounds.append([
                "tag": "http",
                "port": 10809,
                "listen": "127.0.0.1",
                "protocol": "http",
                "settings": [:] as [String: Any]
            ])
        }

        root["inbounds"] = inbounds
        root["log"] = ["loglevel": "warning"]

        guard let newData = try? JSONSerialization.data(withJSONObject: root),
              let json = String(data: newData, encoding: .utf8)
        else { return rawConfig }

        return json
    }

    private func extractProxyPorts(_ config: String) -> (socks: Int, http: Int) {
        guard let data = config.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let inbounds = root["inbounds"] as? [[String: Any]]
        else { return (10808, 10809) }

        var socksPort = 10808
        var httpPort = 10809

        for inbound in inbounds {
            guard let proto = (inbound["protocol"] as? String)?.lowercased()
            else { continue }

            let port = intValue(inbound["port"])

            if proto == "socks", let port { socksPort = port }
            if proto == "http", let port { httpPort = port }
        }

        return (socksPort, httpPort)
    }

    // MARK: - Directories

    private func getSharedDirectory() -> URL {
        let groupId = "group.com.simnetiq.vpnreact"
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupId)
            ?? FileManager.default.temporaryDirectory
    }

    private func getWorkingDirectory() -> URL {
        getSharedDirectory().appendingPathComponent("working", isDirectory: true)
    }

    private func getCacheDirectory() -> URL {
        getSharedDirectory()
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    }

    // MARK: - Response Decoding

    private struct CallResponse {
        let success: Bool
        let data: String?
        let error: String?
    }

    private func decodeCallResponse(_ base64String: String?) -> CallResponse? {
        guard let base64String,
              !base64String.isEmpty,
              let raw = Data(base64Encoded: base64String),
              let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { return nil }

        let success = object["success"] as? Bool ?? false

        let data: String?
        if let str = object["data"] as? String {
            data = str
        } else if let num = object["data"] as? NSNumber {
            data = num.stringValue
        } else {
            data = nil
        }

        let error = object["error"] as? String

        return CallResponse(success: success, data: data, error: error)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

// MARK: - Errors

extension PacketTunnelProvider {
    enum TunnelError: LocalizedError {
        case noConfiguration
        case xrayStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .noConfiguration:
                return "No VPN configuration found."
            case .xrayStartFailed(let reason):
                return "Xray failed to start: \(reason)"
            }
        }
    }
}

// MARK: - Thread-safe one-shot flag for timeout mechanism

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    /// Returns `true` if this is the first call. All subsequent calls return `false`.
    func setIfFirst() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
