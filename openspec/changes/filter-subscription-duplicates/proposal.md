## Why

Subscriptions can import multiple configs that point to the same effective connection, which makes large subscription lists noisy and harder to browse. A default-on duplicate filter keeps imported lists cleaner while still letting users opt out when they need to inspect every raw entry.

## What Changes

- Add a per-subscription setting to filter duplicate imported configs.
- Enable duplicate filtering by default for new and existing subscription sources unless the user explicitly turns it off.
- Apply duplicate filtering during subscription import and refresh so only unique imported configs are shown when the setting is enabled.
- Preserve the ability to disable duplicate filtering for a subscription and keep all imported entries.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `subscription-management`: Change subscription import behavior so a subscription source can filter duplicate imported configs, with the filter enabled by default and configurable per source.

## Impact

- Subscription source model and persistence
- Subscription settings UI in the Connections settings window
- Subscription import/reconciliation pipeline
- Tests for subscription import, persistence, and settings behavior
