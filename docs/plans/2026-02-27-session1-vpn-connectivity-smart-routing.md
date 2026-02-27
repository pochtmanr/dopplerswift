# Session 1: VPN Connectivity Fix + Smart Routing + Debug Infrastructure

**Date:** 2026-02-27
**Status:** Completed

## What Was Done

### Task 1: Fix VPN Internet Connectivity (CRITICAL)
**Problem:** VPN connected via Xray/LibXray but no internet access.

**Root causes found (iteratively):**
1. **No debug visibility** — Network Extension runs as a separate process; NSLog doesn't appear in Xcode console.
2. **Missing mph cache** — Xray tried to load `xray.mph` cache file that didn't exist. Fix: pass empty string for mphCachePath.
3. **Invalid geosite codes** — `geosite:de` doesn't exist in geosite.dat. Fix: use `domain:de` (TLD matching) instead.
4. **TUN black hole** — `includedRoutes = [NEIPv4Route.default()]` captured ALL IP traffic into a TUN interface that Xray doesn't read (it only listens on HTTP/SOCKS ports). DNS and non-HTTP traffic died. Fix: set `includedRoutes = []` and rely purely on HTTP proxy settings.

**Final working architecture:**
- Xray listens on SOCKS (10808) and HTTP (10809) inbound ports
- iOS routes HTTP/HTTPS via `NEProxySettings` (httpServer/httpsServer → 127.0.0.1:10809)
- `proxy.matchDomains = [""]` routes ALL domains through proxy
- No TUN capture — TUN interface exists but no traffic is routed into it
- Server IP excluded from proxy to prevent routing loops
- DNS: 1.1.1.1 + 1.0.0.1 (resolved directly, not through tunnel)

**Files modified:**
- `PulseVPNTunnel/PacketTunnelProvider.swift` — routing, DNS resolution, geoip/geosite copying, debug logging
- `PulseVPNTunnel/Shared/TunnelLogger.swift` — NEW, shared file logger via App Group
- `PulseVPN/Views/TunnelDebugView.swift` — NEW, in-app log viewer

### Task 2: Replace Ad Blocker with Smart Routing
Replaced the non-functional "Ad Blocker" tab with a "Smart Routing" split-tunneling feature.

**How it works:**
- User selects their country (auto-detected via IP geolocation)
- Domestic traffic (TLD domains + geoip ranges) bypasses VPN → goes direct
- Custom domain bypass rules supported
- Xray routing rules: `domain:{country}` for TLD, `geoip:{country}` for IP ranges

**Files modified:**
- `PulseVPN/Views/SmartRoutingView.swift` — NEW, full Smart Routing UI
- `PulseVPN/Services/XrayConfigBuilder.swift` — replaced adBlock with smart routing rules
- `PulseVPN/ContentView.swift` — replaced adBlocker tab with smartRoute
- `PulseVPN/Views/HomeView.swift` — replaced adBlock widget with smart routing widget
- `PulseVPN/Services/ConfigStore.swift` — replaced adBlock persistence with smart routing
- `PulseVPNTunnel/Shared/ConfigStore.swift` — removed adBlock
- `PulseVPN/Views/AdBlockerView.swift` — DELETED

### Post-Session Cleanup
- Moved Tunnel Logs from Profile → App Settings > Developer section
- Fixed nav title: "Doppler VPN" → "Pulse Route"

## Known Issues / Tech Debt
- **Slow Xray startup (~32s):** Loading 19MB geoip.dat. Consider: smaller dat file, lazy loading, or skip geoip rules when smart routing disabled.
- **Connect on Launch / Kill Switch:** AppStorage toggles exist but are non-functional (UI only).
- **HTTP-only proxy:** Non-HTTP traffic (raw TCP, UDP) doesn't go through VPN. This is a limitation of the proxy-only approach without TUN capture.

## Architecture Notes
- **App Group:** `group.com.pulsingroutes.vpn`
- **Bundle ID:** `com.pulsingroutes.vpn`
- **Tunnel Extension:** `PulseVPNTunnel` (NEPacketTunnelProvider)
- **LibXray:** Static library (gomobile-built Xray-core), linked into tunnel binary
- **Geo data:** geoip.dat + geosite.dat bundled in tunnel extension, copied to App Group at startup
