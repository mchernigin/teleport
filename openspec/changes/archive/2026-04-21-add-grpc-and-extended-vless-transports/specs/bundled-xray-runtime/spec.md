## MODIFIED Requirements

### Requirement: Application generates runtime configuration from saved VLESS settings
The system SHALL generate an Xray-compatible runtime configuration from the currently selected saved connection before starting the runtime, including both supported VLESS and supported Trojan configurations.

#### Scenario: Start with valid VLESS gRPC configuration
- **WHEN** the user starts a saved VLESS gRPC configuration
- **THEN** the system generates the matching gRPC stream settings and launches Xray with it

#### Scenario: Start with valid VLESS xHTTP configuration
- **WHEN** the user starts a saved VLESS xHTTP configuration
- **THEN** the system generates the matching xHTTP stream settings and launches Xray with it

#### Scenario: Start with valid Trojan gRPC configuration
- **WHEN** the user starts a saved Trojan gRPC configuration
- **THEN** the system generates the matching gRPC stream settings and launches Xray with it
