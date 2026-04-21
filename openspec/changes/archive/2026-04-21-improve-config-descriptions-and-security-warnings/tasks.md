## 1. Model and parsing

- [x] 1.1 Extend the saved connection model to persist insecure TLS intent in a backward-compatible way.
- [x] 1.2 Parse `insecure=1` and `allowInsecure=1` for supported VLESS and Trojan TLS-based links.
- [x] 1.3 Pass insecure TLS intent through to generated Xray TLS settings when applicable.

## 2. Settings presentation

- [x] 2.1 Replace the generic `VLESS` / `TROJAN` row label with a more descriptive summary.
- [x] 2.2 Show a visible warning marker for configs with no encryption or insecure TLS validation.

## 3. Verification

- [x] 3.1 Add or update focused verification coverage for insecure TLS parsing/persistence behavior.
- [x] 3.2 Verify the macOS app builds successfully with `xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build` after the implementation changes.
