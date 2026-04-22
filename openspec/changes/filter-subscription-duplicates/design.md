## Context

Teleport already supports managed subscription sources with editable per-source settings such as URL, custom name, and auto-update interval. Subscription refresh parses all supported links and atomically replaces imported entries for that source, but it currently keeps every valid entry even when multiple links represent the same effective connection.

This change adds a default-on per-subscription duplicate filter. The implementation must update persistence, settings UI, and the subscription import pipeline while preserving existing user data and selection behavior. Existing saved state may not include the new preference, so the design must provide a safe backward-compatible default.

## Goals / Non-Goals

**Goals:**
- Add a persisted per-subscription boolean that controls duplicate filtering.
- Default the setting to enabled for new subscriptions and for legacy subscriptions loaded from older snapshots.
- Filter duplicate imported entries during subscription refresh when the setting is enabled.
- Keep refresh and reconciliation behavior stable for non-duplicate entries and for sources with filtering disabled.
- Expose the setting in subscription settings with clear user control.

**Non-Goals:**
- Deduplicate across different subscription sources.
- Merge or rewrite manual saved connections.
- Add complex duplicate reporting, analytics, or new UI badges for filtered entries.
- Change how unsupported entries are counted beyond preserving current skipped-entry handling.

## Decisions

### Persist a `filterDuplicateImports` flag on `SubscriptionSource`
A new boolean field will be added to `SubscriptionSource` and included in Codable persistence. Its default value will be `true` in the initializer and in legacy decoding paths when the field is absent.

This keeps the preference local to each subscription source, matches the existing settings model, and avoids special migration steps for older snapshots.

**Alternatives considered:**
- Global app-wide duplicate filtering setting: rejected because users may want different behavior per subscription.
- One-time migration that rewrites saved state: rejected because decode-time defaulting is simpler and lower risk.

### Deduplicate on parsed configuration identity, not raw link text
Duplicate filtering will be based on a canonical key derived from parsed `ConnectionConfiguration` values rather than the raw subscription entry text. The key should ignore cosmetic differences such as remarks or fragment names while preserving fields that materially affect the routed connection, such as protocol type, host, port, security, transport, credential fields, server name, host header, path, ALPN, Reality metadata, gRPC service name, and transport mode.

This better matches the user expectation of "same connection" than raw-link comparison, which would miss duplicates that differ only in labels or formatting.

**Alternatives considered:**
- Raw-link deduplication: too weak because equivalent configs with different names would remain duplicated.
- Host/port-only deduplication: too aggressive because distinct credentials or transport settings could be collapsed incorrectly.

### Keep the first occurrence from each refresh result
When filtering is enabled, the import pipeline will preserve the first imported entry for each canonical duplicate key and drop later duplicates from the same refresh result.

Keeping the first occurrence is deterministic, simple to reason about, and avoids extra ranking logic.

**Alternatives considered:**
- Keep the last occurrence: no clear benefit and less intuitive for ordered subscription payloads.
- Rank by remarks or health data: adds complexity without strong user value.

### Apply duplicate filtering before reconciliation
Filtering will happen after parsing valid subscription links but before `SubscriptionConnectionReconciler` replaces imported entries. This ensures reconciler input already matches the intended stored set and keeps downstream selection and persistence logic unchanged.

**Alternatives considered:**
- Filter after reconciliation: would create extra temporary entries and complicate ID preservation.
- Filter before parsing: impossible to do reliably because duplicate identity depends on parsed configuration data.

## Risks / Trade-offs

- **[Canonical key misses true duplicates or collapses distinct configs]** → Build the key from all connection-defining fields except cosmetic labels and cover with focused tests.
- **[Legacy subscriptions change visible imported lists after upgrade]** → Defaulting old sources to enabled is intentional; document it in proposal/specs and preserve opt-out in settings.
- **[Selection changes when duplicates are removed]** → Rely on existing reconciliation fallback behavior and add tests around refresh with filtered duplicates.
- **[Users want visibility into filtered counts]** → Defer this until there is evidence that the simpler setting is insufficient.

## Migration Plan

1. Add the new persisted `filterDuplicateImports` field with default decode behavior of `true` when missing.
2. Add the setting to the subscription settings sheet and wire save/update flows.
3. Update subscription import to optionally filter duplicates before reconciliation.
4. Verify legacy snapshot decoding, refresh behavior, and disabled-filter behavior with tests.
5. Release without a state migration; rollback is safe because older builds will ignore the extra persisted field.

## Open Questions

- None currently; the duplicate key and default-on behavior are defined for implementation.
