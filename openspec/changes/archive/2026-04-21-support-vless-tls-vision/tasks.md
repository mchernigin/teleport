## 1. Parser support

- [x] 1.1 Update VLESS validation so `flow=xtls-rprx-vision` is accepted for TCP links using either `security=tls` or `security=reality`.
- [x] 1.2 Preserve existing rejections for unsupported transports and unrelated VLESS flow combinations.

## 2. Verification

- [x] 2.1 Add or update focused verification coverage for a VLESS TLS + Vision link.
- [x] 2.2 Verify the macOS app builds successfully with `xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build` after the implementation changes.
