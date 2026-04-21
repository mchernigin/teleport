## Context

Teleport already supports protocol-aware parsing and Xray config generation for a limited set of VLESS and Trojan transports. The main missing piece is a broader transport model and matching stream settings generation. Subscription feeds already encountered by the project include gRPC, xHTTP, and raw variants, so the compatibility gain is immediate and practical.

## Goals / Non-Goals

**Goals**
- Support VLESS transports: gRPC, xHTTP, raw.
- Support Trojan gRPC over TLS.
- Preserve the transport-specific metadata needed to generate Xray stream settings.
- Keep existing supported combinations working.

**Non-Goals**
- Add new protocols such as Shadowsocks or VMess in this change.
- Add every possible transport-specific tuning parameter from provider links.
- Broaden Trojan Reality beyond the currently supported transport rules.

## Decisions

### Extend the transport model directly
The transport enum will grow to include `grpc`, `xhttp`, and `raw` so that supported links round-trip naturally through storage and UI summaries.

### Persist small transport-specific metadata
A minimal set of additional fields will be stored on `ConnectionConfiguration`:
- gRPC service name
- optional transport mode (used for xHTTP and link metadata that should survive round-trip)

This avoids transport-specific parsing hacks and lets runtime config generation remain deterministic.

### Keep validation narrow for Trojan
Trojan will allow gRPC only for TLS-based links. Trojan Reality remains TCP-only in this change.

## Risks / Trade-offs

- xHTTP configuration has more optional provider-specific knobs than Teleport will initially preserve. The implementation should support common links without promising every advanced parameter.
- raw transport support depends on the bundled Xray build recognizing `raw` as a valid network type.
- More supported transports mean more combinations to verify, so focused script coverage is important.
