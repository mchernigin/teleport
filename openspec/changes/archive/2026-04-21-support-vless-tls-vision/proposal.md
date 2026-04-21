## Why

Teleport currently rejects many otherwise usable VLESS links from real-world subscriptions because it only accepts `flow=xtls-rprx-vision` when `security=reality`. Common provider feeds also publish VLESS TLS links that use `xtls-rprx-vision`, and those entries are skipped during manual import and subscription refresh.

## What Changes

- Accept VLESS links that use `security=tls`, `type=tcp`, and `flow=xtls-rprx-vision`.
- Preserve existing validation so unsupported transports and unrelated flow combinations are still rejected.
- Add focused verification coverage for the newly supported VLESS TLS + Vision combination.

## Capabilities

### Modified Capabilities
- `vless-link-management`: Teleport must accept VLESS TLS share links that use `xtls-rprx-vision` over TCP.
- `bundled-xray-runtime`: Generated outbound configuration must continue to pass the selected VLESS flow through to Xray for supported TLS and Reality combinations.

## Impact

- Affected code: VLESS parsing/validation and focused verification coverage.
- Affected UX: More entries from mixed VLESS subscription feeds import successfully instead of being marked unsupported.
