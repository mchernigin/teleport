## Why

The project currently does not provide a native macOS client for connecting to VLESS endpoints through Xray in a minimal, low-friction interface. A menu bar–only v1 enables fast validation of the core product direction: import a VLESS link, manage the bundled Xray runtime, and toggle the macOS system proxy without requiring a full windowed app.

## What Changes

- Add a menu bar–only macOS app flow for a single local user.
- Allow users to add and persist a VLESS share link as the primary connection configuration.
- Bundle Xray core with the app and generate the runtime configuration needed to run it locally.
- Provide controls in the menu bar to start/stop the tunnel runtime and enable/disable the macOS system proxy.
- Show basic connection state in the menu bar UI, including whether a VLESS link is configured, whether Xray is running, and whether system proxy is enabled.
- Keep v1 intentionally minimal: no subscription management, no multi-profile switching, no traffic stats, and no advanced routing editor.

## Capabilities

### New Capabilities
- `menubar-client`: Menu bar–only native macOS client workflow for configuring and controlling the app.
- `vless-link-management`: Import, validate, persist, and use a VLESS link as the source of connection settings.
- `bundled-xray-runtime`: Package Xray core with the app and manage its local process lifecycle.
- `system-proxy-toggle`: Enable and disable the macOS system proxy to route traffic through the local Xray listener.

### Modified Capabilities
- None.

## Impact

- Affected code: SwiftUI/AppKit app structure, menu bar UI, configuration storage, process management, and macOS proxy integration.
- Dependencies/systems: bundled Xray executable, local config file generation, macOS network/proxy settings, and app sandbox/permissions considerations.
- APIs: internal parsing/mapping from VLESS URL to Xray runtime configuration.
