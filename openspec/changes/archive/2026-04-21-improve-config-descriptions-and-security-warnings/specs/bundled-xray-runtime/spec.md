## MODIFIED Requirements

### Requirement: Application generates runtime configuration from saved VLESS settings
The system SHALL generate an Xray-compatible runtime configuration from the currently selected saved connection before starting the runtime, including both supported VLESS and supported Trojan configurations.

#### Scenario: Start with insecure TLS verification enabled
- **WHEN** the user starts a supported TLS-based saved configuration that explicitly allows insecure TLS verification
- **THEN** the generated runtime configuration preserves that TLS setting so the connection behavior matches the imported link
