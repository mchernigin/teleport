## Context

Teleport currently stores only manually entered share links as saved connections. The menu bar picker works well for a small number of entries, but the app does not yet support subscription URLs that return many VLESS or Trojan configs from a single source. Adding subscriptions touches persistence, network fetching, parsing, settings management, and the menu bar browsing flow, so the implementation needs a single design that keeps manual links and subscription-derived entries coherent.

The app is menu bar first, uses a dedicated Settings window for connection management, and already persists selected connection state. The new work must preserve the current Connect / Disconnect behavior while letting users add a subscription URL once and browse the imported options afterward.

## Goals / Non-Goals

**Goals:**
- Add a first-class subscription source model that can be saved in Settings.
- Fetch and parse subscription payloads automatically when a valid subscription URL is added.
- Persist imported entries so they can populate the menu bar picker across relaunches.
- Keep imported entries associated with their subscription source for refresh, replacement, and error reporting.
- Improve the picker behavior so a user can more easily inspect all imported options from the menu bar.
- Reuse existing VLESS and Trojan parsing paths where possible instead of creating a parallel config model.

**Non-Goals:**
- Background periodic refresh while the app is not interacting with the user.
- Editing individual imported entries by hand.
- Provider-specific subscription authentication schemes beyond a standard URL fetch supported by the platform networking stack.
- Hot-swapping the active connection while connected.

## Decisions

### Store subscriptions as sources separate from saved connections
The app will model subscription URLs as source records and keep imported configs as normal selectable saved connections that reference their source. This keeps connection and runtime code focused on a single concept: a selected saved connection. It also allows the UI to distinguish manually added entries from subscription-managed entries.

**Alternatives considered:**
- Store only the raw subscription URL and re-fetch every launch. Rejected because it makes the app dependent on immediate network success to show existing options.
- Flatten everything into saved connections without source metadata. Rejected because refresh, replacement, and source-specific error handling become brittle.

### Parse subscription payloads into the existing protocol-aware connection model
Subscription responses will be decoded into individual VLESS and Trojan share links, then passed through the existing validation/import pipeline for supported protocols. This avoids maintaining separate protocol parsing logic for manual and subscription imports.

**Alternatives considered:**
- Implement an entirely new subscription-only parser that bypasses existing link import. Rejected because it duplicates validation and increases protocol drift risk.

### Replace imported entries atomically per subscription refresh
When a subscription refresh succeeds, the app will build the new imported entry set off the main thread, then replace the prior entries associated with that subscription in a single persistence update. The selected connection should be preserved when an equivalent imported entry still exists after refresh; otherwise the app should fall back predictably.

**Alternatives considered:**
- Incremental diff updates. Rejected for v1 because it adds complexity without clear UX benefit.

### Keep subscription fetch user-driven and visible
The first fetch will happen automatically after adding a subscription URL. Subsequent refresh behavior can be initiated from Settings. Fetch failures should be shown inline instead of silently failing.

**Alternatives considered:**
- Silent fetch with no user-visible state. Rejected because subscription workflows are network-dependent and users need actionable feedback.

### Expose imported options through the existing menu bar picker
The menu bar will continue to use a single picker for selecting the current connection, but it will present all imported entries from subscriptions as normal selectable options. The interaction should be adjusted so users can hover/open and browse the full list more easily.

**Alternatives considered:**
- Split manual and subscription entries into separate controls. Rejected because it complicates the compact menu bar UI.

## Risks / Trade-offs

- **Subscription payloads may contain unsupported or malformed links** → Filter unsupported entries, preserve source-level errors, and import only valid supported entries.
- **Refresh can remove or rename entries that users previously selected** → Preserve selection when a stable imported entry match is available; otherwise show a clear fallback state.
- **Network fetch on add can block UI if done incorrectly** → Run fetch and parsing off the main thread and publish state changes back to the main actor.
- **Large subscriptions may make the picker crowded** → Improve picker interaction and allow Settings to remain the management surface for detailed inspection.
- **Persisted model changes can break existing state** → Extend the snapshot format in a backward-compatible way and keep legacy migration logic intact.

## Migration Plan

1. Extend persisted state to include subscription sources and source metadata on imported saved connections.
2. Preserve existing manual saved connections during migration by defaulting them to source-less entries.
3. On first launch after update, load old state into the expanded model without discarding any saved manual connections.
4. Ship automatic fetch only for newly added subscription URLs in v1; no background migration fetch is required.
5. If rollback is needed, imported subscription entries can be ignored by older builds, but backward compatibility is best-effort because the storage schema will gain new fields.

## Open Questions

- What exact hover behavior is preferred for the menu bar picker if AppKit/SwiftUI limits picker customization in the popover?
- Should a manual refresh action be exposed per subscription source, globally, or both in the initial release?
- What matching rule should define an “equivalent” imported entry when preserving selection across refreshes?
