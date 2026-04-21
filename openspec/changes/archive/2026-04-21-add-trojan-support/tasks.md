## 1. Connection model refactor

- [x] 1.1 Replace the VLESS-specific top-level saved connection model with a protocol-aware active connection model
- [x] 1.2 Preserve shared fields needed by both VLESS and Trojan while isolating protocol-specific authentication/settings
- [x] 1.3 Keep raw-link-based restore behavior so existing saved VLESS links migrate cleanly into the new model

## 2. Link parsing and validation

- [x] 2.1 Refactor the parser entry point to dispatch by link scheme instead of assuming VLESS only
- [x] 2.2 Implement parsing and validation for the supported Trojan share-link subset
- [x] 2.5 Extend Trojan parsing and validation to support Reality links with required metadata
- [x] 2.3 Update validation errors and saved-state handling to use protocol-neutral connection wording where appropriate
- [x] 2.4 Keep existing VLESS parsing behavior working after the protocol-aware refactor

## 3. UI and persistence updates

- [x] 3.1 Update the menu bar UI copy from VLESS-specific wording to connection-link wording
- [x] 3.2 Show enough saved connection information for users to distinguish the active protocol and endpoint
- [x] 3.3 Ensure save/start/stop/proxy actions continue working unchanged for both VLESS and Trojan active configurations

## 4. Xray config generation and runtime support

- [x] 4.1 Refactor runtime config generation to build protocol-specific outbounds behind one config writer entry point
- [x] 4.2 Implement Trojan outbound config generation for the supported subset
- [x] 4.4 Extend Trojan outbound config generation for Reality stream settings
- [x] 4.3 Verify the runtime manager continues to launch bundled Xray correctly for both VLESS and Trojan configurations

## 5. Verification and release-readiness

- [x] 5.1 Add parser/config-generation verification coverage for supported Trojan links
- [x] 5.4 Add verification coverage for Trojan Reality parsing and config generation
- [x] 5.2 Re-run or extend verification coverage to protect existing VLESS behavior after the refactor
- [x] 5.3 Manually verify the menu bar flow for saving a Trojan link, starting Xray, enabling proxy, disabling proxy, and stopping Xray
