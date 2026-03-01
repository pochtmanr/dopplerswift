import Foundation

enum ConnectionStatus: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed

    var displayText: String {
        switch self {
        case .disconnected: String(localized: "Disconnected")
        case .connecting: String(localized: "Connecting...")
        case .connected: String(localized: "Connected")
        case .disconnecting: String(localized: "Disconnecting...")
        case .failed: String(localized: "Connection Failed")
        }
    }

    var isActive: Bool {
        self == .connected || self == .connecting
    }
}
