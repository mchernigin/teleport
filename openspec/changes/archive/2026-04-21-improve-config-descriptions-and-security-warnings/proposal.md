## Why

Settings currently labels connections with only the protocol name and endpoint, which is too vague when many imported configs look similar. Teleport also does not clearly warn when a config disables encryption or weakens TLS verification, even though those properties materially affect user safety.

## What Changes

- Make connection descriptions in Settings more descriptive by showing protocol, security mode, transport, and notable connection traits.
- Persist insecure TLS metadata from imported/manual links so Teleport can recognize configs using `insecure=1` or `allowInsecure=1`.
- Show a visible warning marker for configs that disable encryption or weaken TLS verification.
- Preserve runtime behavior by passing insecure TLS intent through to generated Xray configuration when applicable.

## Capabilities

### Modified Capabilities
- `settings-window`: Saved and imported connections should show descriptive connection details and visible warnings for insecure configurations.
- `vless-link-management`: VLESS parsing should preserve insecure TLS flags needed for warnings and runtime generation.
- `trojan-link-management`: Trojan parsing should preserve insecure TLS flags needed for warnings and runtime generation.
- `bundled-xray-runtime`: Generated runtime config should reflect persisted insecure TLS settings for supported TLS-based connections.

## Impact

- Affected code: connection model, link parsing, runtime config generation, Settings UI, and focused verification scripts.
