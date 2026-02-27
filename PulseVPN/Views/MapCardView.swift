import SwiftUI
import MapKit

// MARK: - Map Card View

struct MapCardView: View {
    let userGeo: IPGeolocation?
    let serverGeo: IPGeolocation?
    let isConnected: Bool
    var isExpanded: Bool = false
    var onToggleExpand: (() -> Void)?

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            mapContent

            // Bottom overlays
            HStack(alignment: .bottom) {
                infoOverlay

                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .contentShape(RoundedRectangle(cornerRadius: Design.CornerRadius.lg))
        .onChange(of: userGeo?.ip) { _, _ in updateCamera() }
        .onChange(of: serverGeo?.ip) { _, _ in updateCamera() }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { updateCamera() }
        }
        .onAppear { updateCamera() }
    }

    // MARK: - Map

    @ViewBuilder
    private var mapContent: some View {
        Map(position: $position, interactionModes: isExpanded ? [.pan, .zoom] : []) {
            // User annotation
            if let coord = userGeo?.coordinate {
                Annotation("You", coordinate: coord) {
                    Image(systemName: "person.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.blue)
                        .background(Circle().fill(.white).frame(width: 24, height: 24))
                }
            }

            // Server annotation
            if let coord = serverGeo?.coordinate {
                Annotation("Server", coordinate: coord) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundStyle(Design.Colors.accent)
                        .background(Circle().fill(.white).frame(width: 24, height: 24))
                }
            }

            // Route line: single geodesic arc user → server
            if let userCoord = userGeo?.coordinate,
               let serverCoord = serverGeo?.coordinate {
                MapPolyline(coordinates: geodesicArc(from: userCoord, to: serverCoord))
                    .stroke(
                        Design.Colors.accent.opacity(0.5),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat))
        // When collapsed, disable map hit testing so card tap gesture works
        .allowsHitTesting(isExpanded)
    }

    // MARK: - Geodesic Arc

    /// Generates intermediate points along a great-circle arc between two coordinates.
    private func geodesicArc(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        segments: Int = 50
    ) -> [CLLocationCoordinate2D] {
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let lon2 = end.longitude * .pi / 180

        let d = acos(
            sin(lat1) * sin(lat2) +
            cos(lat1) * cos(lat2) * cos(lon2 - lon1)
        )

        // If points are essentially the same, return direct line
        guard d > 1e-6 else { return [start, end] }

        return (0...segments).map { i in
            let f = Double(i) / Double(segments)
            let a = sin((1 - f) * d) / sin(d)
            let b = sin(f * d) / sin(d)

            let x = a * cos(lat1) * cos(lon1) + b * cos(lat2) * cos(lon2)
            let y = a * cos(lat1) * sin(lon1) + b * cos(lat2) * sin(lon2)
            let z = a * sin(lat1) + b * sin(lat2)

            let lat = atan2(z, sqrt(x * x + y * y))
            let lon = atan2(y, x)

            return CLLocationCoordinate2D(
                latitude: lat * 180 / .pi,
                longitude: lon * 180 / .pi
            )
        }
    }

    // MARK: - Info Overlay

    @ViewBuilder
    private var infoOverlay: some View {
        HStack(spacing: Design.Spacing.sm) {
            Circle()
                .fill(isConnected ? Design.Colors.connected : Design.Colors.disconnected)
                .frame(width: 6, height: 6)

            if let geo = userGeo {
                Text(geo.shortLocationDisplay)
                    .font(.system(.caption2, design: .rounded, weight: .medium))
                    .foregroundStyle(Design.Colors.textPrimary)
            } else {
                Text("Locating...")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Design.Colors.textSecondary)
            }
        }
        .padding(.horizontal, Design.Spacing.sm)
        .padding(.vertical, Design.Spacing.xs)
        .glassEffect(.regular, in: .capsule)
        .padding(Design.Spacing.sm)
    }

    // MARK: - Camera

    private func updateCamera() {
        let coordinates: [CLLocationCoordinate2D] = [
            userGeo?.coordinate,
            serverGeo?.coordinate
        ].compactMap { $0 }

        guard !coordinates.isEmpty else {
            position = .automatic
            return
        }

        if coordinates.count == 1 {
            position = .region(MKCoordinateRegion(
                center: coordinates[0],
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            ))
            return
        }

        let lats = coordinates.map(\.latitude)
        let lons = coordinates.map(\.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )

        let latDelta = max((lats.max()! - lats.min()!) * 1.6, 5)
        let lonDelta = max((lons.max()! - lons.min()!) * 1.6, 5)

        position = .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        ))
    }
}
