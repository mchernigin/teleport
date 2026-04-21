## MODIFIED Requirements

### Requirement: Menu bar client exposes the primary control surface
The application SHALL present its primary user interface from the macOS menu bar and SHALL allow the user to view selected configuration status, runtime status, and proxy status without opening a separate main window. The menu bar UI MAY open a separate settings window for configuration management, but connection actions SHALL remain available from the menu bar.

#### Scenario: User opens the menu bar UI
- **WHEN** the application is running and the user clicks the menu bar item
- **THEN** the system shows the selected saved connection, connection actions, status information, and a way to open Settings

### Requirement: Menu bar client provides connection actions
The application SHALL provide actions in the menu bar UI to choose a saved connection, connect or disconnect using the selected saved configuration, and open the Settings window to manage connections.

#### Scenario: User sees available actions
- **WHEN** the user opens the menu bar UI
- **THEN** the system presents actions relevant to the current state, including saved-connection selection, connect or disconnect, and opening Settings

### Requirement: Menu bar client shows operational state
The application SHALL show distinct operational states for unconfigured, ready, running, stopped, and failed conditions so the user can understand what action is needed.

#### Scenario: No configuration exists
- **WHEN** no supported connection link has been saved
- **THEN** the system indicates that setup is required before connection can start and offers a path to open Settings

#### Scenario: Runtime launch fails
- **WHEN** the bundled Xray runtime fails to start or exits unexpectedly
- **THEN** the system shows a failed state in the menu bar UI
