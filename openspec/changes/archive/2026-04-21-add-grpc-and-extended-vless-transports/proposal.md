## Why

Teleport currently supports only a narrow transport subset for VLESS and Trojan. Real-world subscription feeds commonly include VLESS gRPC, VLESS xHTTP, VLESS raw, and Trojan gRPC links, which Teleport currently rejects as unsupported even when Xray can consume them.

## What Changes

- Add support for VLESS links using `type=grpc`, `type=xhttp`, and `type=raw`.
- Add support for Trojan links using `type=grpc`.
- Persist any additional transport metadata required to generate working Xray stream settings, such as gRPC service names and xHTTP mode/path settings.
- Update focused verification coverage for the newly supported transport combinations.

## Capabilities

### Modified Capabilities
- `vless-link-management`: Teleport must accept additional supported VLESS transport variants used in real subscriptions.
- `trojan-link-management`: Teleport must accept Trojan TLS links that use gRPC.
- `bundled-xray-runtime`: Generated Xray configuration must preserve the transport-specific stream settings needed for the supported new variants.

## Impact

- Affected code: connection model, link parsing, runtime config generation, verification scripts, and descriptive transport labels.
