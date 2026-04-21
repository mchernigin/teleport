## Why

Teleport currently stores only a single connection, which makes it cumbersome for people who use multiple servers, protocols, or environments. The app needs a simple way to keep several saved configs, switch between them quickly from the menu bar, and manage them in a dedicated settings window without turning the menu bar popover into a full editor.

## What Changes

- Add support for storing multiple saved connection configs instead of a single saved config.
- Add a selected/active config concept so the user can switch between previously saved configs from the menu bar.
- Update the menu bar UI to show a picker for saved configs and connect using the currently selected config.
- Add a Settings window with an initial **Connections** tab for adding and removing saved configs.
- Keep the existing Connect / Disconnect flow, but make it operate on the currently selected saved config.
- Preserve proxy cleanup and Xray shutdown behavior when switching or disconnecting.

## Capabilities

### New Capabilities
- `config-management`: Manage multiple saved connection configs, track the selected config, and expose connection-management UI in Settings.
- `settings-window`: Provide a dedicated app window for settings, starting with a Connections tab.

### Modified Capabilities
- `menubar-client`: Change the menu bar experience from single-config editing to selecting and using an already saved config, plus opening Settings.
- `vless-link-management`: Support storing multiple VLESS links as independent saved configs instead of only one persisted config.
- `trojan-link-management`: Support storing multiple Trojan links as independent saved configs instead of only one persisted config.
- `bundled-xray-runtime`: Run the bundled Xray runtime against the currently selected saved config and handle config switching safely.

## Impact

- App state and persistence models in `teleport/TeleportModels.swift` and `teleport/TeleportServices.swift`
- Menu bar UI in `teleport/MenuBarView.swift`
- App lifecycle and scene setup in `teleport/teleportApp.swift`
- New SwiftUI settings window/views for connection management
- OpenSpec specs for menu bar behavior, config persistence, runtime selection, and settings UI
