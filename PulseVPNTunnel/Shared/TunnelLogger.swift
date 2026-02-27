import Foundation

/// Writes debug logs to a shared file in the App Group container.
/// Both the tunnel extension and the main app can read this file.
enum TunnelLogger {

    private static let appGroupID = "group.com.pulsingroutes.vpn"
    private static let fileName = "tunnel_debug.log"
    private static let maxFileSize = 100_000 // ~100KB, auto-truncate

    private static var logFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Append a log line with timestamp.
    static func log(_ message: String) {
        guard let url = logFileURL else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        NSLog("[Tunnel] %@", message) // Also NSLog for Console.app

        if FileManager.default.fileExists(atPath: url.path) {
            // Truncate if too large
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int, size > maxFileSize {
                try? "--- LOG TRUNCATED ---\n".write(to: url, atomically: true, encoding: .utf8)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Clear the log file.
    static func clear() {
        guard let url = logFileURL else { return }
        try? "".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Read the entire log file.
    static func readAll() -> String {
        guard let url = logFileURL else { return "(no log file)" }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "(empty)"
    }
}
