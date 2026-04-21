## Context

Teleport currently persists a single saved connection and exposes most editing directly inside the menu bar UI. That model no longer scales once the user wants to keep multiple VLESS and Trojan configs, switch between them quickly, and manage their list without overloading the menu bar surface.

This change affects persistence, connection state, runtime startup, and UI structure:
- persistence must evolve from a single persisted configuration to a collection plus selected config identity
- the menu bar must become a lightweight connection surface focused on selection and connect/disconnect
- the app needs a dedicated Settings window for connection management
- runtime and proxy handling must stay safe when the selected config changes

The app remains menu bar-first. The new window is a settings surface, not a primary app window.

## Goals / Non-Goals

**Goals:**
- Support multiple saved configs across supported protocols.
- Let the user pick an already saved config directly from the menu bar.
- Add a Settings window with a first Connections tab for adding and removing configs.
- Preserve the current Connect / Disconnect model and quit/disconnect cleanup guarantees.
- Keep persistence compatible enough to migrate existing single-config users without manual intervention.

**Non-Goals:**
- Building a general multi-tab preferences system beyond the initial Connections tab.
- Supporting folders, tags, search, or sync for saved configs.
- Editing every field of a parsed config through a form UI; input remains share-link based.
- Running multiple configs concurrently.

## Decisions

### 1. Store connections as a collection with a selected config identifier
The app will replace the single persisted configuration snapshot with a collection of saved configurations, each carrying a stable identifier and metadata such as saved date and display name, plus a selected config identifier.

**Why:** this makes quick switching possible without reparsing raw state on every selection and gives the runtime a single source of truth for “active config”.

**Alternatives considered:**
- Reuse the existing single saved slot and keep a separate “recent configs” list: rejected because selection and persistence semantics become inconsistent.
- Store raw links only and derive everything lazily: rejected because the app already depends on parsed configuration state and display metadata.

### 2. Migrate the current menu bar UI to selection-first behavior
The menu bar will stop being the primary place to add/remove all configs. Instead, it will show the selected config, a picker or menu of saved configs, current connection status, Connect / Disconnect, and an action to open Settings.

**Why:** the menu bar should stay fast and compact. Bulk connection management belongs in a dedicated window.

**Alternatives considered:**
- Keep full add/remove/edit controls inside the menu bar: rejected because it expands the compact control surface too much.
- Move all connection actions into the Settings window: rejected because quick connect/disconnect and switching should remain one click away.

### 3. Add a dedicated Settings scene with a Connections tab
The app will expose a settings window containing an initial Connections tab. That tab will list saved configs and provide add/remove actions. Adding a config will remain link-based, with validation using existing parsers.

**Why:** this creates a scalable management surface while keeping the app menu bar-first.

**Alternatives considered:**
- Open a custom standalone NSWindow manually: rejected because SwiftUI settings/window scenes are simpler to maintain in this app.
- Use modal sheets from the menu bar only: rejected because that still ties management to the popover lifecycle.

### 4. Connect / Disconnect always operate on the currently selected saved config
The runtime configuration generator and process lifecycle will use the selected saved config at connect time. If the user changes selection while connected, the app will either block destructive changes or require disconnect before the switch becomes effective.

**Why:** it avoids ambiguous runtime state and keeps proxy cleanup logic predictable.

**Alternatives considered:**
- Hot-swap runtime config while connected: rejected for v1 because it adds state-transition complexity and higher risk around proxy/runtime mismatch.
- Allow selection changes silently while connected and only apply later: possible, but explicit disconnect-first behavior is safer and easier to explain.

### 5. Migrate existing single-config state automatically on load
If the persisted state contains the legacy single-config structure, the app will convert it into the new collection model with one saved entry selected by default.

**Why:** existing users should keep their config without manual re-entry.

**Alternatives considered:**
- Drop legacy state and require reimport: rejected due to poor upgrade experience.

## Risks / Trade-offs

- **State migration bugs could lose an existing saved config** → Add a compatibility loader path that reads legacy snapshots and writes the new format only after successful decode.
- **Selection changes while connected could confuse users** → Disable destructive switching behavior during an active session or require disconnect before applying another config.
- **The Settings window could accidentally become the main app surface** → Keep only management actions there and retain connection status/connect controls in the menu bar.
- **Multiple protocol types increase list-management edge cases** → Use a protocol-agnostic saved-config model with shared metadata and existing parser validation.

## Migration Plan

1. Extend persisted models to support multiple saved configs plus selected config ID.
2. Add legacy-state decoding that maps the old single saved config into the new structure.
3. Update menu bar state binding to read/write selected config from the new store.
4. Add the Settings window and Connections management UI.
5. Verify that existing saved configs survive upgrade and that connect/disconnect still cleans up proxy state.

## Open Questions

- Should selecting a different config while connected be disabled entirely, or allowed with a clear “applies after disconnect” message?
- Should the Connections tab support inline rename for friendly display names, or keep names derived strictly from link metadata for now?
- Should newly added configs become selected automatically, or only after explicit user selection?
