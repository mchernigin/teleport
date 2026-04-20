## Context

This repository is currently a small native macOS app written in Swift with an Xcode project and minimal SwiftUI entry points. The proposed v1 adds a menu bar–only workflow that accepts a single VLESS share link, converts it into an Xray-compatible runtime configuration, starts a bundled Xray process locally, and toggles the system proxy so macOS apps can route traffic through the local listener.

The design must keep scope intentionally narrow for v1: one manually entered VLESS link, one active profile, basic connection state, and local-only behavior. Because the app needs to manage an external runtime and mutate system proxy settings, the design crosses UI, persistence, process management, and OS integration boundaries.

## Goals / Non-Goals

**Goals:**
- Provide a native menu bar UI for adding a VLESS link and controlling connection state.
- Persist a single user-supplied VLESS link and derived connection metadata locally.
- Bundle Xray core with the app and launch it with a generated config derived from the stored VLESS link.
- Allow the user to enable and disable the macOS system proxy from the app.
- Surface enough status to understand whether configuration exists, Xray is running, and proxy is enabled.
- Keep implementation modular so future versions can add multiple profiles, subscriptions, and richer status.

**Non-Goals:**
- Subscription URLs, remote config sync, or profile collections.
- Advanced Xray routing rules, protocol editing, transport customization UI, or custom DNS management.
- Traffic usage statistics, latency measurement, server health checks, or auto-reconnect logic beyond simple process restart handling.
- A full main window–driven UX; v1 is centered on the menu bar experience.
- Non-macOS platforms.

## Decisions

### 1. Use a menu bar app architecture with SwiftUI-backed status/menu content
The app will use a menu bar extra as the primary interaction model. SwiftUI views can render status, actions, and a compact configuration form, while AppKit integration remains available for system services and lifecycle hooks.

**Rationale:** This matches the product goal of a menu bar–only client and avoids overbuilding a multi-window shell for v1.

**Alternatives considered:**
- Standard windowed app first: simpler for forms, but conflicts with the intended UX.
- Pure AppKit status item UI: more control, but slower to iterate and less aligned with the current SwiftUI app skeleton.

### 2. Store exactly one VLESS configuration in local app-managed persistence
The app will persist the raw VLESS link plus a parsed representation needed for validation and display. Persistence can use a small local JSON or UserDefaults-backed store wrapped behind a configuration service.

**Rationale:** v1 needs only one connection definition, and abstracting storage behind a service keeps room for multiple profiles later.

**Alternatives considered:**
- In-memory only: too fragile for a daily-use utility.
- Core Data or SwiftData: unnecessary complexity for one small record.

### 3. Parse the VLESS URL into a normalized internal model before generating Xray config
On save, the app will validate the VLESS link, extract required fields (server, port, UUID, security, transport-related parameters that are supported in v1), and convert them into an internal model. Xray runtime config will be generated from this normalized model rather than from the raw URL at launch time.

**Rationale:** Validation should happen once near input time, and normalization reduces risk of malformed runtime config.

**Alternatives considered:**
- Pass raw link through directly each time: simpler initially, but weak validation and harder debugging.
- Full generic URI/config support: out of scope for v1.

### 4. Bundle Xray as an app resource and run it as a managed child process
The Xray binary will be packaged with the app bundle, copied or referenced from a known executable location at runtime, and launched as a child process with a generated JSON config file stored in an app-controlled writable directory.

**Rationale:** Bundling the runtime removes external installation friction and gives the app explicit control over versioning and process lifecycle.

**Alternatives considered:**
- Require users to install Xray separately: unacceptable for a simple consumer-facing v1.
- Embed static library equivalents: not practical given Xray distribution model.

### 5. Use explicit start/stop lifecycle management with observable state
A dedicated runtime manager will start Xray, capture termination, inspect launch failures, and publish a small state model to the menu bar UI. Connection state will distinguish at least: unconfigured, ready, starting, running, stopping, and failed.

**Rationale:** Process lifecycle is the core operational concern; isolating it improves debuggability and future testability.

**Alternatives considered:**
- Fire-and-forget shell launch: too brittle and poor for status reporting.

### 6. Toggle macOS system proxy only after local listener prerequisites are known
The app will manage proxy state separately from runtime state, but proxy enablement should require a valid local proxy endpoint to be configured. When the user enables proxy, the app updates the relevant macOS network service proxy settings; when disabled, it removes only the settings it owns.

**Rationale:** Separating runtime and proxy state prevents accidental global networking breakage and allows controlled recovery.

**Alternatives considered:**
- Automatically enable proxy whenever Xray starts: convenient, but reduces user control and can create confusing side effects.
- App-local proxy only: does not meet the stated goal of toggling system proxy.

### 7. Start with best-effort support for the common VLESS share-link shape and fail clearly on unsupported variants
V1 will target the common VLESS link formats needed to produce a working client for a basic personal workflow. Unsupported or partially supported parameters will result in explicit validation errors instead of silent misconfiguration.

**Rationale:** The VLESS/Xray ecosystem has many combinations; constraining support is safer for a minimal first release.

**Alternatives considered:**
- Claim broad compatibility immediately: high risk and difficult to test.

## Risks / Trade-offs

- [Bundled executable distribution may require careful signing/notarization handling] → Mitigation: keep runtime packaging isolated and document code signing requirements before release builds.
- [macOS proxy manipulation can vary across network services and user environments] → Mitigation: implement changes through a dedicated proxy service, limit scope to settings owned by the app, and provide clear disabled/error recovery states.
- [VLESS link formats may exceed the subset supported in v1] → Mitigation: validate early, show exact unsupported fields, and scope the first parser to explicitly supported combinations.
- [If Xray starts successfully but upstream connectivity fails, users may think the app is broken] → Mitigation: expose separate runtime/proxy state and preserve error output for troubleshooting.
- [Menu bar–only UX can make configuration editing cramped] → Mitigation: keep the form minimal in v1 and allow a lightweight popover or settings panel if needed without changing the overall menu bar architecture.

## Migration Plan

- No production data migration is required because this is a new capability.
- Introduce local persistence with a default empty state on first launch.
- Package Xray into the app bundle and verify runtime path resolution in development and release builds.
- Add rollback behavior by ensuring the app can stop Xray and disable the proxy cleanly if startup fails or the user turns the feature off.

## Open Questions

- Which subset of VLESS transport/security combinations should be explicitly supported in v1 (for example, TCP+TLS only versus adding Reality/WS support)?
- What local inbound mode should Xray expose for proxying in v1: SOCKS, HTTP, or both?
- Will the app be sandboxed, and if so, do any proxy-management or bundled-executable constraints require entitlement or packaging adjustments?
- Should proxy enablement be per active network service only or applied across all eligible macOS network services?
