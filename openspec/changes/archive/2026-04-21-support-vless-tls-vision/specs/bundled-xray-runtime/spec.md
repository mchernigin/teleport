## MODIFIED Requirements

### Requirement: Application generates runtime configuration from saved VLESS settings
The system SHALL generate an Xray-compatible runtime configuration from the currently selected saved connection before starting the runtime, including both supported VLESS and supported Trojan configurations.

#### Scenario: Start with valid saved VLESS TLS Vision configuration
- **WHEN** the user starts the connection and a valid selected saved VLESS configuration exists with `type=tcp`, `security=tls`, and `flow=xtls-rprx-vision`
- **THEN** the system generates the runtime configuration with that VLESS flow preserved and launches Xray with it
