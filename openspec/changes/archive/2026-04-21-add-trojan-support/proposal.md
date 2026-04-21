## Why

Teleport currently supports importing and running only VLESS links, which prevents users from using Trojan-based servers through the same lightweight macOS menu bar client. Adding scoped Trojan support is a natural next step because the app already has the core runtime, proxy, and persistence plumbing, and the remaining gap is protocol parsing, modeling, and config generation.

## What Changes

- Extend the app to accept Trojan share links in addition to existing VLESS links.
- Generalize the saved connection model so one active configuration can represent either VLESS or Trojan.
- Generate Xray outbound configuration for Trojan connections using the same bundled runtime and local proxy flow.
- Update the menu bar UI and validation messages so the app presents protocol-agnostic connection import rather than VLESS-only copy.
- Keep scope intentionally narrow for the first Trojan release: support the common Trojan TLS and Trojan Reality link shapes and reject unsupported variants with explicit validation errors.

## Capabilities

### New Capabilities
- `trojan-link-management`: Import, validate, persist, and use a Trojan share link as the active connection configuration.

### Modified Capabilities
- `menubar-client`: Update the menu bar workflow and UI copy to support importing and displaying either VLESS or Trojan connections.
- `bundled-xray-runtime`: Extend runtime configuration generation and launch behavior to support Trojan outbounds in addition to VLESS.

## Impact

- Affected code: connection models, link parsing, persistence, menu bar UI labels/messages, and Xray config generation including Trojan Reality stream settings.
- Dependencies/systems: bundled Xray runtime remains the execution engine; no new external runtime dependency is expected.
- APIs: internal connection model will shift from VLESS-specific handling toward a protocol-aware configuration layer.
