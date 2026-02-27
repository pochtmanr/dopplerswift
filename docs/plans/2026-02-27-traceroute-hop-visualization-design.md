# Traceroute Hop Visualization — Lite Trace

**Date:** 2026-02-27
**Scope:** On-device ICMP traceroute with map visualization of network hops

## Summary

Add a "Trace Route" feature to the expanded map card that shows all network hops between the user and VPN server as dots on the map with segmented geodesic arcs.

## Trigger & UX

- Manual: user taps "Trace Route" button on expanded map card
- Button only enabled when VPN is connected (need destination IP)
- Hops stream in live as they're discovered
- Results cached until user re-traces
- Only visible in expanded map (collapsed shows user + server only)

## Architecture

### New Files

1. **`Services/TracerouteService.swift`** — Pure Swift ICMP traceroute
   - `func trace(host: String, maxTTL: Int = 30, timeout: TimeInterval = 2) -> AsyncStream<TraceHop>`
   - SOCK_DGRAM + IPPROTO_ICMP (Apple-approved, no raw sockets)
   - Sends ICMP echo with incrementing TTL
   - Parses Time Exceeded replies for hop IPs
   - Skips private IPs (10.x, 172.16-31.x, 192.168.x)
   - Stops when destination reached or maxTTL hit

2. **`Services/HopGeolocator.swift`** — Batch IP geolocation
   - `func geolocate(ips: [String]) async throws -> [String: HopLocation]`
   - POST to http://ip-api.com/batch (up to 100 IPs)
   - Returns IP → (lat, lon, city, country, isp) mapping
   - Free tier: 45 req/min (one batch per trace)

3. **`Models/TraceHop.swift`** — Data model
   ```swift
   struct TraceHop: Identifiable {
       let hopNumber: Int
       let ip: String?
       let latency: Double?
       var coordinate: CLLocationCoordinate2D?
       var city: String?
       var countryCode: String?
   }
   ```

### Modified Files

4. **`Views/MapCardView.swift`**
   - Add `hops: [TraceHop]` parameter
   - Small orange dot annotations for each geolocated hop
   - Segmented geodesic arcs: User → Hop1 → Hop2 → ... → Server
   - updateCamera includes hop coordinates in bounding region

5. **`Views/HomeView.swift`**
   - "Trace Route" button in expanded map (bottom-left area)
   - States: idle, tracing (spinner), done
   - @State traceHops: [TraceHop] fed by AsyncStream
   - Wire: TracerouteService → HopGeolocator → MapCardView

## Error Handling

- ICMP blocked: "Traceroute unavailable on this network" on map card
- Geolocation fails: show hops without dots (hop number + IP + latency only)
- Timeout hops: skip on map, show count "12 hops (7 located)"

## Constraints

- Max 30 TTL, 2s timeout per hop
- ip-api.com batch: 1 request per trace, max 100 IPs
- No auto-run, no caching expiry (manual only)
- No backend/Supabase changes
- No new dependencies

## Decisions

- Pure Swift over Obj-C library (fits all-Swift codebase, ~200 lines)
- On-device ICMP over server-side MTR (shows real user path)
- ip-api.com batch over per-hop requests (1 request vs 15)
- Manual trigger over auto-on-connect (user controls when to trace)
- Expanded map only (collapsed stays clean with user + server)
