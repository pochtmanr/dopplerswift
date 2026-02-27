import Foundation

// MARK: - Parser Errors

enum VLessParserError: LocalizedError {
    case invalidScheme
    case missingUUID
    case missingHost
    case missingPort
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .invalidScheme:
            return "Invalid URI scheme. Expected vless://."
        case .missingUUID:
            return "UUID is missing from the VLESS URI."
        case .missingHost:
            return "Host address is missing from the VLESS URI."
        case .missingPort:
            return "Port number is missing from the VLESS URI."
        case .invalidPort:
            return "Port number is not a valid integer (1-65535)."
        }
    }
}

// MARK: - Parser

enum VLessParser {

    /// Parses a `vless://` URI string into a `VLessConfig`.
    ///
    /// Format: `vless://uuid@host:port?param1=val1&param2=val2#remark`
    static func parse(_ uriString: String) throws -> VLessConfig {
        let trimmed = uriString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Validate scheme
        let prefix = "vless://"
        guard trimmed.lowercased().hasPrefix(prefix) else {
            throw VLessParserError.invalidScheme
        }

        let withoutScheme = String(trimmed.dropFirst(prefix.count))

        // 2. Split fragment (#remark)
        let (beforeFragment, remark) = splitOnce(withoutScheme, separator: "#")

        // 3. Split query string (?)
        let (authority, queryString) = splitOnce(beforeFragment, separator: "?")

        // 4. Parse authority — uuid@host:port
        let (uuid, hostPort) = try parseAuthority(authority)

        // 5. Parse host and port
        let (host, port) = try parseHostPort(hostPort)

        // 6. Parse query parameters
        let params = parseQueryParams(queryString)

        // 7. Build config
        let decodedRemark = remark
            .removingPercentEncoding ?? remark

        return VLessConfig(
            id: UUID(),
            address: host,
            port: port,
            uuid: uuid,
            flow: params["flow"],
            security: params["security"] ?? "none",
            sni: params["sni"],
            publicKey: params["pbk"],
            shortId: params["sid"],
            fingerprint: params["fp"],
            network: params["type"] ?? "tcp",
            path: params["path"]?.removingPercentEncoding,
            serviceName: params["serviceName"],
            remark: decodedRemark.isEmpty ? host : decodedRemark,
            rawURI: trimmed
        )
    }

    // MARK: - Private Helpers

    /// Splits a string on the first occurrence of `separator`.
    /// Returns the part before and the part after. If separator is absent,
    /// the second element is an empty string.
    private static func splitOnce(
        _ string: String,
        separator: Character
    ) -> (String, String) {
        guard let index = string.firstIndex(of: separator) else {
            return (string, "")
        }
        let before = String(string[string.startIndex..<index])
        let after = String(string[string.index(after: index)...])
        return (before, after)
    }

    /// Parses `uuid@host:port` into (uuid, "host:port").
    private static func parseAuthority(
        _ authority: String
    ) throws -> (String, String) {
        guard let atIndex = authority.firstIndex(of: "@") else {
            throw VLessParserError.missingUUID
        }

        let uuid = String(authority[authority.startIndex..<atIndex])
        guard !uuid.isEmpty else {
            throw VLessParserError.missingUUID
        }

        let hostPort = String(authority[authority.index(after: atIndex)...])
        guard !hostPort.isEmpty else {
            throw VLessParserError.missingHost
        }

        return (uuid, hostPort)
    }

    /// Parses `host:port` into (host, port).
    /// Supports IPv6 bracket notation: `[::1]:443`.
    private static func parseHostPort(
        _ hostPort: String
    ) throws -> (String, Int) {
        let host: String
        let portString: String

        if hostPort.hasPrefix("[") {
            // IPv6: [address]:port
            guard let closingBracket = hostPort.firstIndex(of: "]") else {
                throw VLessParserError.missingHost
            }
            host = String(
                hostPort[hostPort.index(after: hostPort.startIndex)..<closingBracket]
            )
            let afterBracket = hostPort.index(after: closingBracket)
            guard afterBracket < hostPort.endIndex,
                  hostPort[afterBracket] == ":" else {
                throw VLessParserError.missingPort
            }
            portString = String(
                hostPort[hostPort.index(after: afterBracket)...]
            )
        } else {
            // IPv4 or hostname: host:port
            let (h, p) = splitOnce(hostPort, separator: ":")
            host = h
            portString = p
        }

        guard !host.isEmpty else {
            throw VLessParserError.missingHost
        }

        guard !portString.isEmpty else {
            throw VLessParserError.missingPort
        }

        guard let port = Int(portString),
              (1...65535).contains(port) else {
            throw VLessParserError.invalidPort
        }

        return (host, port)
    }

    /// Parses a URL query string into a dictionary.
    /// Example: `"security=tls&sni=example.com"` -> `["security": "tls", "sni": "example.com"]`
    private static func parseQueryParams(
        _ queryString: String
    ) -> [String: String] {
        guard !queryString.isEmpty else { return [:] }

        var params: [String: String] = [:]

        for pair in queryString.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let key = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            params[String(key)] = value.removingPercentEncoding ?? value
        }

        return params
    }
}
