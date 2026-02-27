import Foundation

enum XrayConfigBuilder {

    // MARK: - Public API

    static func buildJSON(
        from config: VLessConfig,
        smartRoutingCountry: String? = nil,
        smartRoutingCustomDomains: [String] = [],
        bypassTLDWebsites: Bool = true,
        bypassDomesticIPs: Bool = true
    ) -> String {
        let outbounds: [[String: Any]] = [
            buildProxyOutbound(from: config),
            ["tag": "direct", "protocol": "freedom"],
            ["tag": "block", "protocol": "blackhole"]
        ]

        var root: [String: Any] = [:]
        var routingRules: [[String: Any]] = []

        // Smart Routing: route domestic traffic via direct outbound
        if let country = smartRoutingCountry, !country.isEmpty {
            let code = country.lowercased()

            // Route country TLD domains direct (e.g., .de, .fr, .ru)
            if bypassTLDWebsites {
                routingRules.append([
                    "type": "field",
                    "domain": ["domain:\(code)"],
                    "outboundTag": "direct"
                ])
            }

            // Route domestic IPs direct via geoip database
            // Covers government/banking, streaming, and e-commerce traffic
            if bypassDomesticIPs {
                routingRules.append([
                    "type": "field",
                    "ip": ["geoip:\(code)"],
                    "outboundTag": "direct"
                ])
            }
        }

        // Custom domain bypass rules
        if !smartRoutingCustomDomains.isEmpty {
            let domainPatterns = smartRoutingCustomDomains.map { domain -> String in
                // Prefix with "domain:" for subdomain matching
                if domain.hasPrefix("domain:") || domain.hasPrefix("full:") || domain.hasPrefix("regexp:") {
                    return domain
                }
                return "domain:\(domain)"
            }

            routingRules.append([
                "type": "field",
                "domain": domainPatterns,
                "outboundTag": "direct"
            ])
        }

        // Default: route all remaining traffic through the proxy
        routingRules.append([
            "type": "field",
            "network": "tcp,udp",
            "outboundTag": "proxy"
        ])

        root["routing"] = [
            "domainStrategy": "IPIfNonMatch",
            "rules": routingRules
        ]

        root["outbounds"] = outbounds

        guard let data = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return "{}"
        }

        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Outbound Builder

    private static func buildProxyOutbound(from config: VLessConfig) -> [String: Any] {
        var user: [String: Any] = [
            "id": config.uuid,
            "encryption": "none"
        ]
        if let flow = config.flow, !flow.isEmpty {
            user["flow"] = flow
        }

        let vnextEntry: [String: Any] = [
            "address": config.address,
            "port": config.port,
            "users": [user]
        ]

        let settings: [String: Any] = [
            "vnext": [vnextEntry]
        ]

        let outbound: [String: Any] = [
            "tag": "proxy",
            "protocol": "vless",
            "settings": settings,
            "streamSettings": buildStreamSettings(from: config)
        ]

        return outbound
    }

    // MARK: - Stream Settings

    private static func buildStreamSettings(from config: VLessConfig) -> [String: Any] {
        var stream: [String: Any] = [
            "network": config.network,
            "security": config.security
        ]

        switch config.security {
        case "reality":
            stream["realitySettings"] = buildRealitySettings(from: config)
        case "tls":
            stream["tlsSettings"] = buildTLSSettings(from: config)
        default:
            break
        }

        switch config.network {
        case "ws":
            if let path = config.path {
                stream["wsSettings"] = ["path": path]
            }
        case "grpc":
            if let serviceName = config.serviceName {
                stream["grpcSettings"] = ["serviceName": serviceName]
            }
        case "h2":
            if let path = config.path {
                stream["httpSettings"] = ["path": path]
            }
        default:
            break
        }

        return stream
    }

    // MARK: - Security Settings

    private static func buildRealitySettings(from config: VLessConfig) -> [String: Any] {
        var settings: [String: Any] = [
            "show": false,
            "spiderX": ""
        ]

        if let sni = config.sni {
            settings["serverName"] = sni
        }
        if let fingerprint = config.fingerprint {
            settings["fingerprint"] = fingerprint
        }
        if let publicKey = config.publicKey {
            settings["publicKey"] = publicKey
        }
        if let shortId = config.shortId {
            settings["shortId"] = shortId
        }

        return settings
    }

    private static func buildTLSSettings(from config: VLessConfig) -> [String: Any] {
        var settings: [String: Any] = [:]

        if let sni = config.sni {
            settings["serverName"] = sni
        }
        if let fingerprint = config.fingerprint {
            settings["fingerprint"] = fingerprint
        }

        return settings
    }
}
