# Startup Optimization + Connect on Launch / Kill Switch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce Xray startup from ~32s to ~3-5s by stripping geoip.dat, and make Connect on Launch + Kill Switch toggles functional.

**Architecture:** Strip geoip.dat to 12 countries using a Python script (protobuf decode/re-encode). Enable mph cache for geosite. Wire Connect on Launch to auto-connect in ContentView.onAppear. Wire Kill Switch to NEOnDemandRules via VPNManager.

**Tech Stack:** Swift/SwiftUI, NetworkExtension, Python (for one-time geoip stripping), protobuf

---

### Task 1: Strip geoip.dat to 12 Countries

**Files:**
- Create: `scripts/strip-geoip.py` (one-time utility, not part of app)
- Modify: `PulseVPNTunnel/geoip.dat` (replace 18MB with ~1-2MB stripped version)

**Step 1: Install protobuf Python dependency**

Run: `pip3 install protobuf`

**Step 2: Create the stripping script**

The v2fly geoip.dat is a protobuf file using this schema:
```protobuf
message GeoIP {
  string country_code = 1;
  repeated CIDR cidr = 2;
}
message GeoIPList {
  repeated GeoIP entry = 1;
}
message CIDR {
  bytes ip = 1;
  uint32 prefix = 2;
}
```

Create `scripts/strip-geoip.py`:

```python
#!/usr/bin/env python3
"""Strip geoip.dat to only include specified countries."""

import sys
import os

# v2fly geoip.dat uses protobuf — we parse it manually with the protobuf library
# The proto schema is defined in v2fly/v2ray-core
# We use a self-contained approach: decode raw protobuf without .proto compilation

from google.protobuf import descriptor_pb2
from google.protobuf.internal.decoder import _DecodeVarint
from google.protobuf.internal.encoder import _EncodeVarint

KEEP_COUNTRIES = {"DE", "RU", "US", "GB", "FR", "NL", "TR", "UA", "KZ", "AE", "IL", "CN"}

def read_varint(data, pos):
    result, new_pos = _DecodeVarint(data, pos)
    return result, new_pos

def write_varint(value):
    pieces = []
    _EncodeVarint(pieces.append, value)
    return b''.join(pieces)

def parse_geoip_entries(data):
    """Parse GeoIPList: repeated GeoIP (field 1, length-delimited)."""
    entries = []
    pos = 0
    while pos < len(data):
        # Read field tag
        tag, pos = read_varint(data, pos)
        field_number = tag >> 3
        wire_type = tag & 0x7

        if wire_type == 2:  # length-delimited
            length, pos = read_varint(data, pos)
            entry_data = data[pos:pos + length]
            pos += length

            if field_number == 1:  # GeoIP entry
                # Parse country_code (field 1, string) from the entry
                country_code = parse_country_code(entry_data)
                entries.append((country_code, entry_data))
        else:
            break  # unexpected

    return entries

def parse_country_code(entry_data):
    """Extract country_code (field 1) from a GeoIP message."""
    pos = 0
    while pos < len(entry_data):
        tag, pos = read_varint(entry_data, pos)
        field_number = tag >> 3
        wire_type = tag & 0x7

        if wire_type == 2:  # length-delimited
            length, pos = read_varint(entry_data, pos)
            if field_number == 1:
                return entry_data[pos:pos + length].decode('utf-8')
            pos += length
        elif wire_type == 0:  # varint
            _, pos = read_varint(entry_data, pos)
        else:
            break
    return ""

def rebuild_geoip_list(entries):
    """Re-encode a GeoIPList from filtered entries."""
    result = b''
    for country_code, entry_data in entries:
        # Field 1, wire type 2 (length-delimited)
        tag = write_varint((1 << 3) | 2)
        length = write_varint(len(entry_data))
        result += tag + length + entry_data
    return result

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <input.dat> <output.dat>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, 'rb') as f:
        data = f.read()

    print(f"Input: {len(data)} bytes")

    entries = parse_geoip_entries(data)
    print(f"Total entries: {len(entries)}")
    for cc, _ in entries:
        if cc.upper() in KEEP_COUNTRIES:
            print(f"  KEEP: {cc}")

    filtered = [(cc, d) for cc, d in entries if cc.upper() in KEEP_COUNTRIES]
    print(f"Filtered entries: {len(filtered)}")

    output = rebuild_geoip_list(filtered)

    with open(output_path, 'wb') as f:
        f.write(output)

    print(f"Output: {len(output)} bytes ({len(output) / len(data) * 100:.1f}% of original)")

if __name__ == '__main__':
    main()
```

**Step 3: Run the script to create stripped geoip.dat**

Run:
```bash
cd /Users/romanpochtman/Developer/Pulseroute/PulseVPN
python3 scripts/strip-geoip.py PulseVPNTunnel/geoip.dat PulseVPNTunnel/geoip-stripped.dat
```

Expected: Output ~1-2MB file with 12 country entries.

**Step 4: Replace the original geoip.dat**

Run:
```bash
cp PulseVPNTunnel/geoip.dat PulseVPNTunnel/geoip-full.dat.bak
mv PulseVPNTunnel/geoip-stripped.dat PulseVPNTunnel/geoip.dat
ls -lh PulseVPNTunnel/geoip.dat
```

Expected: geoip.dat now ~1-2MB.

**Step 5: Commit**

```bash
git add PulseVPNTunnel/geoip.dat scripts/strip-geoip.py
git commit -m "perf: strip geoip.dat to 12 countries (18MB → ~1MB)"
```

---

### Task 2: Enable mph Cache for Geosite

**Files:**
- Modify: `PulseVPNTunnel/PacketTunnelProvider.swift:74` (change mphCachePath)

**Step 1: Set mphCachePath to cache directory**

In `PacketTunnelProvider.swift`, change line 74 from:
```swift
let mphCachePath = ""
```
to:
```swift
let mphCachePath = cacheDir.path
```

This lets Xray cache the domain matcher after first build, speeding up subsequent startups.

**Step 2: Build and verify tunnel extension compiles**

Run: `xcodebuild -scheme PulseVPN -destination 'generic/platform=iOS' build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add PulseVPNTunnel/PacketTunnelProvider.swift
git commit -m "perf: enable mph cache for geosite domain matching"
```

---

### Task 3: Implement Connect on Launch

**Files:**
- Modify: `PulseVPN/ContentView.swift` (add auto-connect in performInitialLoad)

**Step 1: Add connect-on-launch logic to performInitialLoad()**

In `ContentView.swift`, modify `performInitialLoad()` (currently at line 329):

```swift
private func performInitialLoad() {
    servers = ConfigStore.loadServers()
    selectedServerID = ConfigStore.loadSelectedServerID()

    Task {
        await loadCloudServers()
        await detectCountry()

        // Connect on Launch: auto-connect if enabled and we have a saved server
        if UserDefaults.standard.bool(forKey: "connectOnLaunch"),
           let server = servers.first(where: { $0.id == selectedServerID }),
           vpnManager.status == .disconnected {
            try? await convertAndConnect(server.vlessConfig)
        }
    }
}
```

Key points:
- Reads `connectOnLaunch` from standard UserDefaults (matches @AppStorage in AppSettingsView)
- Only triggers if VPN is disconnected (avoids double-connect)
- Requires both a selected server and servers loaded
- Uses existing `convertAndConnect` method

**Step 2: Build and verify**

Run: `xcodebuild -scheme PulseVPN -destination 'generic/platform=iOS' build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add PulseVPN/ContentView.swift
git commit -m "feat: implement connect on launch toggle"
```

---

### Task 4: Implement Kill Switch (On-Demand Rules)

**Files:**
- Modify: `PulseVPN/Services/VPNManager.swift` (add setKillSwitch method + on-demand rules)
- Modify: `PulseVPN/Views/AppSettingsView.swift` (wire toggle to VPNManager)

**Step 1: Add kill switch method to VPNManager**

In `VPNManager.swift`, add after the `disconnect()` method (line 58):

```swift
func setKillSwitch(enabled: Bool) async {
    // Need an existing manager to configure on-demand rules
    if manager == nil {
        await loadManager()
    }
    guard let manager else { return }

    if enabled {
        // Always connect — if VPN drops, iOS will reconnect automatically
        let connectRule = NEOnDemandRuleConnect()
        connectRule.interfaceTypeMatch = .any
        manager.onDemandRules = [connectRule]
        manager.isOnDemandEnabled = true
    } else {
        manager.onDemandRules = []
        manager.isOnDemandEnabled = false
    }

    do {
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
    } catch {
        errorMessage = "Failed to update kill switch: \(error.localizedDescription)"
    }
}
```

Also apply on-demand rules during install/update so kill switch persists across reconnects. In `installManager(xrayJSON:)`, before `try await newManager.saveToPreferences()`:

```swift
// Apply kill switch if enabled
if UserDefaults.standard.bool(forKey: "killSwitch") {
    let connectRule = NEOnDemandRuleConnect()
    connectRule.interfaceTypeMatch = .any
    newManager.onDemandRules = [connectRule]
    newManager.isOnDemandEnabled = true
}
```

Same in `updateManagerConfig(xrayJSON:)`, before `try await manager.saveToPreferences()`:

```swift
// Preserve kill switch setting
if UserDefaults.standard.bool(forKey: "killSwitch") {
    let connectRule = NEOnDemandRuleConnect()
    connectRule.interfaceTypeMatch = .any
    manager.onDemandRules = [connectRule]
    manager.isOnDemandEnabled = true
} else {
    manager.onDemandRules = []
    manager.isOnDemandEnabled = false
}
```

**Step 2: Wire AppSettingsView toggle to VPNManager**

In `AppSettingsView.swift`, add VPNManager dependency and onChange handler:

```swift
struct AppSettingsView: View {
    let vpnManager: VPNManager

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("connectOnLaunch") private var connectOnLaunch = false
    @AppStorage("killSwitch") private var killSwitch = false

    var body: some View {
        List {
            Section("Connection") {
                Toggle("Connect on Launch", isOn: $connectOnLaunch)
                Toggle("Kill Switch", isOn: $killSwitch)
            }

            Section("Notifications") {
                Toggle("Push Notifications", isOn: $notificationsEnabled)
            }

            Section("Developer") {
                NavigationLink {
                    TunnelDebugView()
                } label: {
                    Label("Tunnel Logs", systemImage: "ant.fill")
                }
            }
        }
        .navigationTitle("App Settings")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onChange(of: killSwitch) {
            Task {
                await vpnManager.setKillSwitch(enabled: killSwitch)
            }
        }
    }
```

**Step 3: Update all call sites passing vpnManager to AppSettingsView**

Search for `AppSettingsView()` in the codebase and add the `vpnManager:` parameter.

Run: `grep -rn "AppSettingsView()" PulseVPN/PulseVPN/`

Update each call site to `AppSettingsView(vpnManager: vpnManager)`.

**Step 4: Build and verify**

Run: `xcodebuild -scheme PulseVPN -destination 'generic/platform=iOS' build 2>&1 | tail -5`

**Step 5: Commit**

```bash
git add PulseVPN/Services/VPNManager.swift PulseVPN/Views/AppSettingsView.swift
git commit -m "feat: implement kill switch using NEOnDemandRules"
```

---

### Task 5: Verify and Clean Up

**Step 1: Full build check**

Run: `xcodebuild -scheme PulseVPN -destination 'generic/platform=iOS' build 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

**Step 2: Remove backup file**

```bash
rm PulseVPNTunnel/geoip-full.dat.bak
```

**Step 3: Final commit if any cleanup needed**

```bash
git add -A && git commit -m "chore: cleanup after startup optimization"
```
