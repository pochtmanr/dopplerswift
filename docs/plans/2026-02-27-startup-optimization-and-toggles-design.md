# Design: Xray Startup Optimization + Connect on Launch / Kill Switch

**Date:** 2026-02-27
**Status:** Approved

## Task 1: Optimize Xray Startup (~32s → ~3-5s)

### Problem
Xray takes ~32s to start because it parses a 19MB geoip.dat containing every country.

### Solution
1. **Strip geoip.dat** to only include ~12 countries: DE, RU, US, GB, FR, NL, TR, UA, KZ, AE, IL, CN
   - Use v2fly/geoip tooling or a Python script to extract entries from the protobuf-encoded dat file
   - Replace the 19MB file with a ~1-2MB stripped version in the tunnel bundle
2. **Add file existence check** — only copy geo files to App Group if they don't already exist (skip redundant copies on subsequent launches)
3. **Enable mph cache** — set `mphCachePath` to App Group directory instead of `""` so geosite domain matching is cached after first run

### Files Modified
- `PulseVPNTunnel/PacketTunnelProvider.swift` — existence check + mph cache path
- `PulseVPNTunnel/geoip.dat` — replaced with stripped version

## Task 2: Connect on Launch + Kill Switch

### Problem
Both toggles exist in AppSettingsView as @AppStorage but do nothing.

### Connect on Launch
- In ContentView's `.onAppear`, check `@AppStorage("connectOnLaunch")`
- If true and a saved server/config exists, call `vpnManager.connect()` automatically
- Only triggers on fresh app launch (not tab switches)

### Kill Switch
- Use iOS native **On-Demand Rules** (`NEOnDemandRuleConnect`)
- When kill switch toggled ON: set `manager.isOnDemandEnabled = true` with a connect-always rule, save preferences
- When kill switch toggled OFF: set `isOnDemandEnabled = false`, save preferences
- This makes iOS auto-reconnect VPN if it drops, preventing unprotected traffic
- AppSettingsView toggle calls VPNManager method directly (not just writing to UserDefaults)

### Files Modified
- `PulseVPN/Services/VPNManager.swift` — add `setKillSwitch(enabled:)` method, add on-demand rules
- `PulseVPN/Views/ContentView.swift` — add connect-on-launch logic in `.onAppear`
- `PulseVPN/Views/AppSettingsView.swift` — wire kill switch toggle to VPNManager

## Architecture Notes
- Connect on Launch only needs main app UserDefaults (no App Group needed)
- Kill Switch modifies NETunnelProviderManager directly via VPNManager
- On-Demand rules are the standard iOS mechanism for kill switch behavior
- mph cache stored in App Group so tunnel extension can read/write it
