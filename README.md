# Teleport

Teleport is a small macOS menu bar app for running a local Xray-based proxy with VLESS and Trojan links.

## Features

- menu bar-only app
- bundled Xray runtime
- support for `vless://` and `trojan://` links
- only system proxy for now (Tun mode will be added later)

## Build

Open `teleport.xcodeproj` in Xcode and run the `teleport` scheme.

Or build from the command line:

```bash
xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build
```
