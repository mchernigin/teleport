# Teleport

Teleport is a small macOS menu bar app for running a local Xray-based proxy with VLESS, Trojan, and subscription-based connection imports.

## Features

- menu bar-only app
- bundled Xray runtime
- support for `vless://` and `trojan://` links
- support for `http://` and `https://` subscription URLs that fetch and import multiple configs
- saved connections with persistent selection across launches
- lightweight server health checks with persisted sampled TCP latency and availability state
- dedicated Settings window for connection and subscription management
- System Proxy mode for apps that respect macOS proxy settings
- VPN mode using Xray's privileged TUN inbound for full-device IPv4 routing

## Connection modes

### System Proxy

System Proxy mode starts the bundled Xray runtime as the current user, exposes local SOCKS/HTTP proxy ports, and enables macOS system proxy settings. It works for apps that honor system proxy configuration and does not require administrator approval.

### VPN

VPN mode starts Xray with its TUN inbound using administrator privileges. Teleport asks macOS for an admin password because creating a TUN interface and changing routes requires root access.

VPN mode installs split default IPv4 routes:

```text
0.0.0.0/1   -> Xray utun
128.0.0.0/1 -> Xray utun
```

It also protects the selected proxy server with a host route through the original network gateway so Xray's own outbound connection does not loop back into the tunnel.

Disconnect other VPN apps before using VPN mode. If another VPN owns the default `utun` route, Teleport refuses to start VPN mode; use System Proxy mode when another VPN must remain active.

Runtime diagnostics for VPN mode are written under:

```text
~/Library/Application Support/teleport/xray-tun.log
~/Library/Application Support/teleport/xray-tun-control.log
~/Library/Application Support/teleport/xray-tun-session.json
```

## Build

Open `teleport.xcodeproj` in Xcode and run the `teleport` scheme.

Or build from the command line:

```bash
xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build
```

## Subscription verification script

A focused verification script for subscription parsing, persistence, and selection preservation is available at:

```bash
swiftc teleport/TeleportModels.swift teleport/Connection/*.swift teleport/Parsing/*.swift teleport/Persistence/*.swift teleport/Subscriptions/*.swift teleport/Xray/*.swift teleport/Proxy/*.swift teleport/Health/*.swift teleport/ViewModels/*.swift scripts/verify_subscription_support.swift -o /tmp/verify_subscription_support && /tmp/verify_subscription_support
```

## Connection health verification script

A focused verification script for health metadata persistence, freshness classification, and subscription reconciliation is available at:

```bash
swiftc teleport/TeleportModels.swift teleport/Connection/*.swift teleport/Parsing/*.swift teleport/Persistence/*.swift teleport/Subscriptions/*.swift teleport/Xray/*.swift teleport/Proxy/*.swift teleport/Health/*.swift teleport/ViewModels/*.swift scripts/verify_connection_health.swift -o /tmp/verify_connection_health && /tmp/verify_connection_health
```
