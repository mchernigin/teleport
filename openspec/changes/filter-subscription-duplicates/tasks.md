## 1. Data model and persistence

- [x] 1.1 Add a persisted `filterDuplicateImports` flag to `SubscriptionSource` with a default value of `true`.
- [x] 1.2 Update subscription decoding and snapshot restore paths so legacy saved sources without the new flag default to duplicate filtering enabled.
- [x] 1.3 Extend subscription settings update flows to save and preserve the duplicate-filter preference.

## 2. Subscription import behavior

- [x] 2.1 Define a canonical duplicate key for imported `ConnectionConfiguration` values that ignores cosmetic labels but preserves connection-defining fields.
- [x] 2.2 Apply duplicate filtering during subscription import and refresh before reconciliation when the source setting is enabled.
- [x] 2.3 Preserve existing behavior when duplicate filtering is disabled, including import ordering and reconciliation of imported entries.

## 3. Settings UI

- [x] 3.1 Add a duplicate-filter toggle to the subscription settings sheet with default-on behavior for newly created sources.
- [x] 3.2 Ensure the subscription settings UI reflects the saved preference when editing an existing source.
- [x] 3.3 Keep subscription refresh and settings-save flows working correctly after the new setting is introduced.

## 4. Verification

- [x] 4.1 Add or update tests for duplicate filtering enabled versus disabled during subscription import.
- [x] 4.2 Add or update tests for legacy persistence compatibility and default-on restore behavior.
- [x] 4.3 Run the project verification/build commands and confirm the change is ready to apply.
