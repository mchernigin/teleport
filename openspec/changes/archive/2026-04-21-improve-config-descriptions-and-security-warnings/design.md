## Context

Teleport already stores protocol, transport, security, flow, endpoint, and related transport metadata for saved connections, but Settings only renders a minimal `PROTOCOL • host:port` summary. The parser also currently ignores `insecure=1` and `allowInsecure=1`, so the app cannot explain that a TLS-based config skips normal certificate validation.

## Goals / Non-Goals

**Goals**
- Provide a concise but more useful Settings summary for each connection.
- Mark clearly insecure configurations in Settings.
- Persist and honor insecure TLS flags for both VLESS and Trojan TLS-based links.
- Keep backward compatibility with older saved state.

**Non-Goals**
- Add deep cryptographic auditing or provider trust scoring.
- Judge every non-Reality config as unsafe; warnings should be tied to explicit weak settings.
- Rework the menu bar connection picker text in this change.

## Decisions

### Represent insecure TLS explicitly on the configuration model
A dedicated boolean flag will record whether the imported link opted into insecure TLS verification. This is clearer than trying to re-derive it later from the raw link everywhere.

### Treat two cases as warning-worthy
The UI will show a warning when:
- `security=none`
- TLS-based configuration has `insecure=1` or `allowInsecure=1`

### Use short descriptive summaries
Settings rows will show a compact summary combining protocol, security, transport, and notable traits such as Vision flow or insecure TLS, while keeping the endpoint visible on a separate line.

## Risks / Trade-offs

- Some users may interpret warnings as absolute judgments rather than practical safety hints. The wording should stay factual and concise.
- Backward compatibility requires defaulting the new insecure-TLS field for older saved snapshots.
