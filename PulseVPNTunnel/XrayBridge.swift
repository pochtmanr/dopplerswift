import Foundation
import LibXray

// MARK: - Call Response

struct CallResponse: Decodable, Sendable {
    let success: Bool
    let data: String?
}

// MARK: - Errors

enum XrayBridgeError: LocalizedError {
    case startFailed(String)
    case stopFailed(String)
    case conversionFailed(String)
    case portAllocationFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .startFailed(let reason):
            return "Xray failed to start: \(reason)"
        case .stopFailed(let reason):
            return "Xray failed to stop: \(reason)"
        case .conversionFailed(let reason):
            return "Share link conversion failed: \(reason)"
        case .portAllocationFailed:
            return "Failed to allocate free ports"
        case .invalidResponse:
            return "Invalid or undecodable response from LibXray"
        }
    }
}

// MARK: - Xray Bridge

enum XrayBridge {

    // MARK: - Public API

    static func run(datDir: String, configJSON: String) throws {
        let base64Input = try encodeRequest([
            "datDir": datDir,
            "mphCachePath": "",
            "configJSON": configJSON
        ])
        let raw = LibXrayRunXrayFromJSON(base64Input)
        let response = try decodeResponse(raw)

        guard response.success else {
            throw XrayBridgeError.startFailed(response.data ?? "unknown error")
        }
    }

    static func stop() throws {
        let raw = LibXrayStopXray()
        let response = try decodeResponse(raw)

        guard response.success else {
            throw XrayBridgeError.stopFailed(response.data ?? "unknown error")
        }
    }

    static var version: String {
        LibXrayXrayVersion()
    }

    static func convertShareLinksToJSON(_ shareLinks: String) throws -> String {
        let base64Input = try encodeRequest(["text": shareLinks])
        let raw = LibXrayConvertShareLinksToXrayJson(base64Input)
        let response = try decodeResponse(raw)

        guard response.success, let json = response.data else {
            throw XrayBridgeError.conversionFailed(response.data ?? "unknown error")
        }
        return json
    }

    static func getFreePorts(_ count: Int) throws -> [Int] {
        let raw = LibXrayGetFreePorts(count)
        let response = try decodeResponse(raw)

        guard response.success, let portString = response.data else {
            throw XrayBridgeError.portAllocationFailed
        }

        let ports = portString
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard ports.count == count else {
            throw XrayBridgeError.portAllocationFailed
        }

        return ports
    }

    // MARK: - Private Helpers

    private static func decodeResponse(_ base64String: String) throws -> CallResponse {
        guard let data = Data(base64Encoded: base64String) else {
            throw XrayBridgeError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(CallResponse.self, from: data)
        } catch {
            throw XrayBridgeError.invalidResponse
        }
    }

    private static func encodeRequest(_ dict: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return data.base64EncodedString()
    }
}
