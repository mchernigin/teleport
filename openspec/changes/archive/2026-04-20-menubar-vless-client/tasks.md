## 1. App skeleton and menu bar UI

- [x] 1.1 Convert the app entry point to a menu bar–first experience using a MenuBarExtra or equivalent status item flow
- [x] 1.2 Build a compact menu bar view that shows configuration, runtime, and proxy status
- [x] 1.3 Add menu actions for saving a VLESS link, starting or stopping Xray, and enabling or disabling the system proxy
- [x] 1.4 Represent UI-visible states for unconfigured, ready, running, stopped, starting, stopping, and failed conditions

## 2. VLESS configuration handling

- [x] 2.1 Define a normalized Swift model for the supported v1 VLESS configuration fields
- [x] 2.2 Implement VLESS link parsing and validation for the supported input subset
- [x] 2.3 Surface explicit validation errors for malformed or unsupported links in the menu bar UI
- [x] 2.4 Persist the active VLESS link and derived configuration locally and restore it on launch

## 3. Bundled Xray runtime integration

- [x] 3.1 Add the Xray core binary to the app bundle/resources and ensure it is accessible as an executable at runtime
- [x] 3.2 Implement generation of an Xray JSON config from the normalized VLESS model
- [x] 3.3 Create a runtime manager that launches Xray as a child process with the generated config
- [x] 3.4 Implement runtime stop, termination handling, and failure reporting back to observable app state

## 4. macOS system proxy management

- [x] 4.1 Define the local proxy endpoint settings that Xray will expose for v1
- [x] 4.2 Implement a proxy service that enables macOS proxy settings only when the local endpoint is available
- [x] 4.3 Implement proxy disable/reset behavior that removes only the settings managed by the app
- [x] 4.4 Reflect proxy success and failure states in the menu bar UI

## 5. Verification and release-readiness

- [x] 5.1 Test the end-to-end flow: save valid VLESS link, start Xray, enable proxy, disable proxy, stop Xray
- [x] 5.2 Test error paths for malformed links, unsupported links, Xray startup failure, and proxy enablement before runtime readiness
- [x] 5.3 Document any required signing, packaging, or local permission considerations for shipping a bundled Xray-based macOS app
