import Foundation

enum ConnectionStatus: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed

    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .disconnecting: "Disconnecting..."
        case .failed: "Connection Failed"
        }
    }

    var isActive: Bool {
        self == .connected || self == .connecting
    }
}
