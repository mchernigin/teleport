## MODIFIED Requirements

### Requirement: Application generates runtime configuration from saved VLESS settings
The system SHALL generate an Xray-compatible runtime configuration from the currently selected saved connection before starting the runtime, including both supported VLESS and supported Trojan configurations.

#### Scenario: Start with valid saved VLESS configuration
- **WHEN** the user starts the connection and a valid selected saved VLESS configuration exists
- **THEN** the system generates the runtime configuration and launches Xray with it

#### Scenario: Start with valid saved Trojan TLS configuration
- **WHEN** the user starts the connection and a valid selected saved Trojan TLS configuration exists
- **THEN** the system generates the runtime configuration and launches Xray with it

#### Scenario: Start with valid saved Trojan Reality configuration
- **WHEN** the user starts the connection and a valid selected saved Trojan Reality configuration exists
- **THEN** the system generates the runtime configuration and launches Xray with it

### Requirement: Application manages Xray process lifecycle
The system SHALL start and stop the bundled Xray runtime based on Connect and Disconnect actions for the currently selected saved configuration and SHALL track whether the process is currently active.

#### Scenario: Start runtime successfully
- **WHEN** the user starts the connection with a valid selected saved configuration
- **THEN** the system launches the bundled Xray process and reports it as running

#### Scenario: Stop runtime successfully
- **WHEN** the user disconnects while the Xray process is running
- **THEN** the system terminates the Xray process and reports it as stopped
