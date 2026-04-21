## 1. Subscription model and persistence

- [x] 1.1 Add persisted models for subscription sources, imported-entry source metadata, and any migration helpers needed to load older manual-only state.
- [x] 1.2 Update configuration storage load/save paths so subscription sources and imported entries round-trip correctly across relaunches.
- [x] 1.3 Preserve or recover the selected connection when subscription-managed entries are refreshed or removed.

## 2. Subscription fetch and import pipeline

- [x] 2.1 Implement subscription URL validation and add-flow handling in the view model or service layer.
- [x] 2.2 Implement subscription fetching, payload decoding, and parsing into individual candidate share links off the main thread.
- [x] 2.3 Reuse the existing VLESS and Trojan import/validation pipeline to convert valid subscription entries into saved connections while tracking skipped entries and fetch errors.
- [x] 2.4 Replace imported entries atomically for one subscription source without affecting manual entries or other sources.

## 3. Settings window experience

- [x] 3.1 Extend the Connections tab to accept subscription URLs in addition to manual share links.
- [x] 3.2 Show saved subscription sources, their imported entries or counts, and visible fetch/parse errors in the Settings UI.
- [x] 3.3 Add a user-driven refresh action for saved subscription sources and wire its state back into the UI.

## 4. Menu bar selection experience

- [x] 4.1 Update the menu bar picker data source to include subscription-imported entries alongside manual connections.
- [x] 4.2 Adjust the picker interaction or presentation so the full set of available options is easier to browse from the menu bar popover.
- [x] 4.3 Ensure connect/disconnect behavior continues to operate on the currently selected imported or manual connection without allowing unsafe switching while connected.

## 5. Verification and documentation

- [x] 5.1 Add or update focused tests/scripts for subscription parsing, persistence, and selection preservation behavior.
- [x] 5.2 Update README and relevant OpenSpec/main specs notes if user-visible subscription workflows require documentation changes.
- [x] 5.3 Verify the macOS app builds successfully with `xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build` after the implementation changes.
