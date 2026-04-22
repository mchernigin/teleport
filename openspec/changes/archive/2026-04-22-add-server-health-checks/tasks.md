## 1. Model and persistence updates

- [x] 1.1 Add a persisted health-metadata model for saved connections, including state, checked timestamp, latency, and failure summary fields.
- [x] 1.2 Update snapshot load/save logic so legacy state files decode without health metadata and new probe results round-trip correctly.
- [x] 1.3 Add freshness helpers that classify restored probe results as fresh, stale, or unknown for UI use.

## 2. Probe service implementation

- [x] 2.1 Implement a background connection-health probe service that measures endpoint connect latency with timeout handling and bounded concurrency.
- [x] 2.2 Integrate probe scheduling into the app view model for initial checks, manual refresh, debouncing, and result publication back to the main actor.
- [x] 2.3 Persist probe results incrementally and keep connect/disconnect flows independent from probe execution.

## 3. Settings and menu bar surfaces

- [x] 3.1 Update the Connections settings rows for manual and imported connections to show health state, latency, stale/unknown state, and refresh actions.
- [x] 3.2 Add subscription-level health refresh handling that triggers probes for imported connections without mutating subscription config data.
- [x] 3.3 Update the menu bar connection picker to show compact health context and expose a refresh action suitable for quick server comparison.

## 4. Verification and follow-through

- [x] 4.1 Add focused tests or verification scripts for probe result classification, persistence compatibility, and refresh-state transitions.
- [x] 4.2 Build the app with `xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build` and fix any integration issues.
- [x] 4.3 Update user-facing documentation or README text if the feature introduces new health terminology or refresh behavior.
