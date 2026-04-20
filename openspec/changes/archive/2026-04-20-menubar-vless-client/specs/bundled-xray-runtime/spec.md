## ADDED Requirements

### Requirement: Application bundles an Xray runtime
The application SHALL include a compatible Xray core runtime as part of the app distribution so the user does not need to install Xray separately.

#### Scenario: App starts on a supported system
- **WHEN** the user launches the application on a supported macOS system
- **THEN** the system has access to the bundled Xray runtime needed for connection operations

### Requirement: Application generates runtime configuration from saved VLESS settings
The system SHALL generate an Xray-compatible runtime configuration from the saved active VLESS connection before starting the runtime.

#### Scenario: Start with valid saved configuration
- **WHEN** the user starts the connection and a valid saved VLESS configuration exists
- **THEN** the system generates the runtime configuration and launches Xray with it

### Requirement: Application manages Xray process lifecycle
The system SHALL allow the user to start and stop the bundled Xray runtime and SHALL track whether the process is currently active.

#### Scenario: Start runtime successfully
- **WHEN** the user starts the connection with a valid saved configuration
- **THEN** the system launches the bundled Xray process and reports it as running

#### Scenario: Stop runtime successfully
- **WHEN** the user stops the connection while the Xray process is running
- **THEN** the system terminates the Xray process and reports it as stopped
