## MODIFIED Requirements

### Requirement: Menu bar client exposes the primary control surface
The application SHALL present its primary user interface from the macOS menu bar and SHALL allow the user to view selected configuration status, runtime status, and proxy status without opening a separate main window. The menu bar UI MAY open a separate settings window for configuration management, but connection actions SHALL remain available from the menu bar.

#### Scenario: User opens the menu bar UI
- **WHEN** the application is running and the user clicks the menu bar item
- **THEN** the system shows the selected saved connection, connection actions, status information, and a way to open Settings

### Requirement: Menu bar client provides connection actions
The application SHALL provide actions in the menu bar UI to choose a saved connection, connect or disconnect using the selected saved configuration, and open the Settings window to manage connections. The saved-connection picker SHALL include subscription-derived entries alongside manually added entries.

#### Scenario: User sees available actions
- **WHEN** the user opens the menu bar UI
- **THEN** the system presents actions relevant to the current state, including saved-connection selection, connect or disconnect, and opening Settings

#### Scenario: User sees imported subscription options in picker
- **WHEN** subscription sources have imported saved connections
- **THEN** the menu bar picker presents those imported entries as selectable options

### Requirement: Menu bar client shows operational state
The application SHALL show distinct operational states for unconfigured, ready, running, stopped, and failed conditions so the user can understand what action is needed.

#### Scenario: No configuration exists
- **WHEN** no supported connection link has been saved
- **THEN** the system indicates that setup is required before connection can start and offers a path to open Settings

#### Scenario: Runtime launch fails
- **WHEN** the bundled Xray runtime fails to start or exits unexpectedly
- **THEN** the system shows a failed state in the menu bar UI

## ADDED Requirements

### Requirement: Menu bar picker supports efficient browsing of many options
The system SHALL make all available connection options discoverable from the menu bar picker when the user interacts with it, including subscription-imported entries that increase the number of choices.

#### Scenario: Browse all connection options from the picker
- **WHEN** the user hovers over or opens the connection picker in the menu bar UI
- **THEN** the system reveals the full set of available connection options without requiring the user to open Settings first
