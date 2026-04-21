## 1. Model and parsing

- [x] 1.1 Extend the transport model to represent `grpc`, `xhttp`, and `raw` in a backward-compatible way.
- [x] 1.2 Parse and persist the additional transport metadata required for VLESS gRPC/xHTTP/raw and Trojan gRPC links.
- [x] 1.3 Update protocol validation rules so VLESS accepts the new transports and Trojan TLS accepts gRPC.

## 2. Runtime config generation

- [x] 2.1 Generate correct Xray stream settings for gRPC transport.
- [x] 2.2 Generate correct Xray stream settings for xHTTP and raw VLESS transports.

## 3. Verification

- [x] 3.1 Add or update focused verification coverage for VLESS gRPC, VLESS xHTTP/raw, and Trojan gRPC.
- [x] 3.2 Verify the macOS app builds successfully with `xcodebuild -project teleport.xcodeproj -scheme teleport -configuration Debug build` after the implementation changes.
