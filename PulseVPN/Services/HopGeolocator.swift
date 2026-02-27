import Foundation
import CoreLocation

// MARK: - Hop Geolocator

/// Batch-geolocates IP addresses using ip-api.com's free batch endpoint.
/// Supports up to 100 IPs per request, 45 requests/minute on free tier.
enum HopGeolocator {

    struct GeoResult: Decodable {
        let status: String
        let query: String
        let lat: Double?
        let lon: Double?
        let city: String?
        let countryCode: String?
        let isp: String?
    }

    /// Geolocates an array of IPs in a single batch request.
    /// Returns a dictionary mapping IP → location data.
    static func geolocate(ips: [String]) async throws -> [String: HopLocation] {
        guard !ips.isEmpty else { return [:] }

        // ip-api.com batch: POST array of IPs, get back array of results
        let url = URL(string: "http://ip-api.com/batch?fields=status,query,lat,lon,city,countryCode,isp")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ips)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            NSLog("[HopGeolocator] Bad response: %@", String(data: data, encoding: .utf8) ?? "")
            throw GeolocatorError.badResponse
        }

        let results = try JSONDecoder().decode([GeoResult].self, from: data)

        var locations: [String: HopLocation] = [:]

        for result in results where result.status == "success" {
            if let lat = result.lat, let lon = result.lon {
                locations[result.query] = HopLocation(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    city: result.city,
                    countryCode: result.countryCode,
                    isp: result.isp
                )
            }
        }

        NSLog("[HopGeolocator] Geolocated %d/%d IPs", locations.count, ips.count)
        return locations
    }

    enum GeolocatorError: LocalizedError {
        case badResponse

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Failed to geolocate hop IPs"
            }
        }
    }
}

// MARK: - Hop Location

struct HopLocation {
    let coordinate: CLLocationCoordinate2D
    let city: String?
    let countryCode: String?
    let isp: String?
}
