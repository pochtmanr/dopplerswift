import SwiftUI
import MapKit

// MARK: - Map Card View

struct MapCardView: View {
    let userGeo: IPGeolocation?
    let serverGeo: IPGeolocation?
    let isConnected: Bool
    var isExpanded: Bool = false
    var hops: [TraceHop] = []
    var onToggleExpand: (() -> Void)?

    @State private var position: MapCameraPosition = .automatic

    // Height is controlled externally via .aspectRatio() in HomeView

    /// Hops that have valid coordinates for map display.
    private var geolocatedHops: [TraceHop] {
        hops.filter { $0.isGeolocated }
    }

    /// All waypoints in order: user → hops → server.
    private var allWaypoints: [CLLocationCoordinate2D] {
        var points: [CLLocationCoordinate2D] = []
        if let coord = userGeo?.coordinate { points.append(coord) }
        points.append(contentsOf: geolocatedHops.compactMap(\.coordinate))
        if let coord = serverGeo?.coordinate { points.append(coord) }
        return points
    }

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
        .onChange(of: hops.count) { _, _ in updateCamera() }
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

            // Hop annotations (only when expanded and hops exist)
            if isExpanded {
                ForEach(geolocatedHops) { hop in
                    if let coord = hop.coordinate {
                        Annotation("Hop \(hop.hopNumber)", coordinate: coord) {
                            ZStack {
                                Circle()
                                    .fill(.orange)
                                    .frame(width: 10, height: 10)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                }
            }

            // Route lines
            if geolocatedHops.isEmpty {
                // No hops: single geodesic arc user → server
                if let userCoord = userGeo?.coordinate,
                   let serverCoord = serverGeo?.coordinate {
                    MapPolyline(coordinates: geodesicArc(from: userCoord, to: serverCoord))
                        .stroke(
                            Design.Colors.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                        )
                }
            } else {
                // Hops exist: segmented arcs through waypoints
                ForEach(0..<max(allWaypoints.count - 1, 0), id: \.self) { i in
                    MapPolyline(coordinates: geodesicArc(from: allWaypoints[i], to: allWaypoints[i + 1]))
                        .stroke(
                            .orange.opacity(0.6),
                            style: StrokeStyle(lineWidth: 2, dash: [6, 3])
                        )
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        // When collapsed, disable map hit testing so card tap gesture works
        .allowsHitTesting(isExpanded)
    }

    // MARK: - Hop Count Badge

    @ViewBuilder
    private var hopCountBadge: some View {
        let total = hops.count
        let located = geolocatedHops.count

        Text("\(total) hops (\(located) located)")
            .font(.system(.caption2, design: .rounded, weight: .medium))
            .foregroundStyle(Design.Colors.textPrimary)
            .padding(.horizontal, Design.Spacing.sm)
            .padding(.vertical, Design.Spacing.xs)
            .glassEffect(.regular, in: .capsule)
            .padding(Design.Spacing.sm)
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

    /// Invisible overlay in the top-right corner that always receives taps,
    /// even when the Map is interactive. Sized to cover the expand button area.
    @ViewBuilder
    private var collapseHitArea: some View {
        if isExpanded {
            VStack {
                HStack {
                    Spacer()
                    Color.clear
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onToggleExpand?()
                        }
                        .padding(Design.Spacing.xs)
                }
                Spacer()
            }
        }
    }

    // MARK: - Expand / Collapse Button

    @ViewBuilder
    private var expandButton: some View {
        Button {
            onToggleExpand?()
        } label: {
            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.caption)
                .foregroundStyle(Design.Colors.textPrimary)
                .padding(Design.Spacing.sm)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
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
        var coordinates: [CLLocationCoordinate2D] = [
            userGeo?.coordinate,
            serverGeo?.coordinate
        ].compactMap { $0 }

        // Include hop coordinates when expanded
        if isExpanded {
            coordinates.append(contentsOf: geolocatedHops.compactMap(\.coordinate))
        }

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
