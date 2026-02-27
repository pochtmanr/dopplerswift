import Foundation

// MARK: - Subscription Errors

enum SubscriptionError: LocalizedError {
    case invalidURL
    case fetchFailed(String)
    case decodeFailed
    case noServers

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The subscription URL is invalid."
        case .fetchFailed(let reason):
            return "Failed to fetch subscription: \(reason)"
        case .decodeFailed:
            return "Could not decode the subscription response."
        case .noServers:
            return "No VLESS servers found in the subscription."
        }
    }
}

// MARK: - Subscription Service

enum SubscriptionService {

    /// Fetches a Marzban subscription URL and parses VLESS configs from the response.
    ///
    /// The response body may be base64-encoded (standard Marzban format) or plain text.
    /// Each line starting with `vless://` is parsed into a `VLessConfig`.
    ///
    /// - Parameter url: The subscription URL string.
    /// - Returns: An array of parsed `VLessConfig` values.
    /// - Throws: `SubscriptionError` if the URL is invalid, the fetch fails,
    ///   the body cannot be decoded, or no servers are found.
    static func fetch(url: String) async throws -> [VLessConfig] {
        // 1. Validate URL
        guard let requestURL = URL(string: url) else {
            throw SubscriptionError.invalidURL
        }

        // 2. Fetch data
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(from: requestURL)
        } catch {
            throw SubscriptionError.fetchFailed(error.localizedDescription)
        }

        // 3. Check HTTP status
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw SubscriptionError.fetchFailed(
                "HTTP \(httpResponse.statusCode)"
            )
        }

        // 4. Decode body as string
        guard let bodyString = String(data: data, encoding: .utf8) else {
            throw SubscriptionError.decodeFailed
        }

        // 5. Try base64 decode (Marzban format), fall back to plain text
        let content = decodeBase64IfNeeded(bodyString)

        // 6. Split by newlines, filter VLESS URIs
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.lowercased().hasPrefix("vless://") }

        // 7. Parse each line, skipping invalid entries
        let configs: [VLessConfig] = lines.compactMap { line in
            try? VLessParser.parse(line)
        }

        // 8. Ensure we found at least one server
        guard !configs.isEmpty else {
            throw SubscriptionError.noServers
        }

        // 9. Return parsed configs
        return configs
    }

    // MARK: - Private Helpers

    /// Attempts to base64-decode the given string. Returns the decoded result
    /// if successful, otherwise returns the original string unchanged.
    private static func decodeBase64IfNeeded(_ string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // Standard base64 requires padding to a multiple of 4
        let padded = addBase64PaddingIfNeeded(trimmed)

        guard let decodedData = Data(base64Encoded: padded),
              let decoded = String(data: decodedData, encoding: .utf8) else {
            return string
        }

        return decoded
    }

    /// Adds `=` padding to a base64 string if its length is not a multiple of 4.
    private static func addBase64PaddingIfNeeded(_ string: String) -> String {
        let remainder = string.count % 4
        guard remainder != 0 else { return string }
        return string + String(repeating: "=", count: 4 - remainder)
    }
}
