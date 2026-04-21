## Why

Teleport currently assumes every saved connection is entered manually as a single share link. That works for one-off VLESS or Trojan imports, but it does not cover the common workflow where a provider distributes a subscription URL that resolves to many connection options and updates over time. Users also need a faster way to browse those options from the menu bar without repeatedly opening Settings.

## What Changes

- Add support for saving subscription URLs as managed sources in the Connections settings.
- Automatically fetch and parse subscription contents after a valid subscription URL is added.
- Persist the subscription source and its fetched connection entries so they can be selected later.
- Surface subscription-derived connection entries in the menu bar connection picker.
- Update the menu bar picker interaction so hovering the picker reveals the full list of available connection options more easily.
- Show subscription-related errors and refresh state in a user-visible way when fetching or parsing fails.

## Capabilities

### New Capabilities
- `subscription-management`: Manage subscription sources, fetch their contents, parse supported configs, and persist the imported connection entries.

### Modified Capabilities
- `config-management`: Saved connections must support entries that originate from a subscription source in addition to manual links.
- `settings-window`: The Connections tab must support adding and displaying subscription sources and their imported entries.
- `menubar-client`: The menu bar picker must present subscription-derived options and support easier browsing of all available entries.
- `vless-link-management`: VLESS configs must be importable from subscription payloads, not only from direct manual entry.
- `trojan-link-management`: Trojan configs must be importable from subscription payloads, not only from direct manual entry.

## Impact

- Affected code: connection persistence models, Settings UI, menu bar picker UI, link parsing/import flow, and app state management.
- Affected systems: local persisted state, network fetching for subscription refresh, and selection logic for imported entries.
- Dependencies: Foundation networking/decoding utilities for subscription fetch and parsing.
