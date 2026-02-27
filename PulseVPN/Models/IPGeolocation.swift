import Foundation
import CoreLocation

// MARK: - IP Geolocation

/// Lightweight model mapping to the `ipapi.co/json/` response.
struct IPGeolocation: Codable, Sendable {
    let ip: String
    let city: String?
    let country: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case ip, city, country, latitude, longitude
        case countryCode = "country_code"
    }

    /// CoreLocation coordinate, nil if lat/lon missing.
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Short location string using country code, e.g. "Berlin, DE".
    var shortLocationDisplay: String {
        switch (city, countryCode) {
        case let (city?, code?):
            return "\(city), \(code)"
        case let (nil, code?):
            return code
        case let (city?, nil):
            return city
        case (nil, nil):
            return "Unknown"
        }
    }

    /// Human-readable location string, e.g. "Berlin, Germany".
    var locationDisplay: String {
        switch (city, country) {
        case let (city?, country?):
            return "\(city), \(country)"
        case let (nil, country?):
            return country
        case let (city?, nil):
            return city
        case (nil, nil):
            return "Unknown"
        }
    }
}
