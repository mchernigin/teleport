## Context

Teleport already stores the parsed VLESS flow on `ConnectionConfiguration` and already writes that flow into the generated Xray outbound user object. The current limitation is stricter parser validation: `xtls-rprx-vision` is only accepted for VLESS Reality TCP links. In practice, some providers also publish VLESS TLS TCP links with the same flow, and Xray can consume them.

## Goals / Non-Goals

**Goals**
- Expand VLESS validation to accept TLS TCP links with `xtls-rprx-vision`.
- Keep existing behavior unchanged for unsupported transports and unsupported flow values.
- Verify the supported combination with a focused script-level check.

**Non-Goals**
- Add support for gRPC, xHTTP, raw, or other new transports.
- Add support for additional protocols such as Shadowsocks.
- Broaden support for arbitrary VLESS flow values.

## Decisions

### Allow Vision for VLESS on TCP with either TLS or Reality
The parser will treat `flow=xtls-rprx-vision` as supported when the transport is TCP and the security is either TLS or Reality. This reflects the new intended support matrix while keeping the rule explicit and narrow.

### Keep outbound generation unchanged
No runtime config schema changes are required because Teleport already preserves `vlessFlow` and emits it into the Xray outbound user configuration. The work is primarily parser validation plus verification coverage.

## Risks / Trade-offs

- Some provider links may still fail due to unrelated unsupported features such as unsupported transports. This change intentionally improves one compatibility gap without claiming full subscription compatibility.
- Expanding the accepted matrix slightly increases the parser surface, so verification should cover both the new TLS case and the existing Reality case.
