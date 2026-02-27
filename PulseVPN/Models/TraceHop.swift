import Foundation
import CoreLocation

struct TraceHop: Identifiable {
    let id = UUID()
    let hopNumber: Int
    let ip: String?
    let latency: Double?        // milliseconds
    var loss: Double?            // packet loss percentage
    var coordinate: CLLocationCoordinate2D?
    var city: String?
    var countryCode: String?
    var isp: String?

    var isGeolocated: Bool {
        coordinate != nil
    }

    var isTimeout: Bool {
        ip == nil
    }
}
