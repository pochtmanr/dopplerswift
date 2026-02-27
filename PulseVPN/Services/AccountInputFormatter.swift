import Foundation

// MARK: - Account Input Formatter

enum AccountInputFormatter {

    private static let prefix = "VPN-"
    private static let totalLength = 19 // VPN-XXXX-XXXX-XXXX
    private static let segmentLength = 4
    private static let hyphenPositions: Set<Int> = [3, 8, 13]

    /// Formats raw user input into `VPN-XXXX-XXXX-XXXX` format.
    ///
    /// Strips non-alphanumeric characters, forces uppercase,
    /// auto-prepends "VPN-" if missing, and inserts hyphens.
    static func format(_ input: String) -> String {
        let uppercased = input.uppercased()

        // Extract only alphanumeric characters, stripping any existing prefix/hyphens
        var raw: String
        if uppercased.hasPrefix("VPN") {
            let afterPrefix = uppercased.dropFirst(3)
            raw = String(afterPrefix.filter { $0.isLetter || $0.isNumber })
        } else {
            raw = String(uppercased.filter { $0.isLetter || $0.isNumber })
        }

        // Limit to 12 chars (3 groups of 4)
        let maxContentLength = segmentLength * 3
        if raw.count > maxContentLength {
            raw = String(raw.prefix(maxContentLength))
        }

        // Build formatted string: VPN-XXXX-XXXX-XXXX
        var result = "VPN"
        for (index, char) in raw.enumerated() {
            if index % segmentLength == 0 {
                result.append("-")
            }
            result.append(char)
        }

        // Cap at max length
        if result.count > totalLength {
            result = String(result.prefix(totalLength))
        }

        return result
    }

    /// Returns `true` when the string exactly matches `VPN-XXXX-XXXX-XXXX`
    /// where X is an uppercase alphanumeric character.
    static func isValid(_ input: String) -> Bool {
        let pattern = #"^VPN-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$"#
        return input.range(of: pattern, options: .regularExpression) != nil
    }
}
