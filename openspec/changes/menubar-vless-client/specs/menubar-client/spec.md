## ADDED Requirements

### Requirement: Menu bar client exposes the primary control surface
The application SHALL present its primary user interface from the macOS menu bar and SHALL allow the user to view configuration status, runtime status, and proxy status without opening a separate main window.

#### Scenario: User opens the menu bar UI
- **WHEN** the application is running and the user clicks the menu bar item
- **THEN** the system shows controls and status for the configured VLESS connection, Xray runtime, and system proxy

### Requirement: Menu bar client provides connection actions
The application SHALL provide actions in the menu bar UI to save a VLESS link, start or stop the bundled runtime, and enable or disable the system proxy.

#### Scenario: User sees available actions
- **WHEN** the user opens the menu bar UI
- **THEN** the system presents actions relevant to the current state, including configuration, runtime control, and proxy control

### Requirement: Menu bar client shows operational state
The application SHALL show distinct operational states for unconfigured, ready, running, stopped, and failed conditions so the user can understand what action is needed.

#### Scenario: No configuration exists
- **WHEN** no VLESS link has been saved
- **THEN** the system indicates that setup is required before connection can start

#### Scenario: Runtime launch fails
- **WHEN** the bundled Xray runtime fails to start or exits unexpectedly
- **THEN** the system shows a failed state in the menu bar UI
