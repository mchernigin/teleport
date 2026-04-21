# Teleport

Teleport is a small macOS menu bar app for running a local Xray-based proxy with VLESS, Trojan, and subscription-based connection imports.

## Features

- menu bar-only app
- bundled Xray runtime
- support for `vless://` and `trojan://` links
- support for `http://` and `https://` subscription URLs that fetch and import multiple configs
- saved connections with persistent selection across launches
- dedicated Settings window for connection and subscription management
- only system proxy for now (Tun mode will be added later)

## Build

Open `teleport.xcodeproj` in Xcode and run the `teleport` scheme.

Or build from the command line:

```bash
xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build
```

## Subscription verification script

A focused verification script for subscription parsing, persistence, and selection preservation is available at:

```bash
swift teleport/TeleportModels.swift teleport/TeleportServices.swift scripts/verify_subscription_support.swift
```
