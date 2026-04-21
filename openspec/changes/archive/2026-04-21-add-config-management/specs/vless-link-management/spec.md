## MODIFIED Requirements

### Requirement: User can add a VLESS link
The system SHALL allow the user to input a VLESS share link and save it as a saved connection configuration that can coexist with other saved connections. The user SHALL be able to select that saved VLESS configuration for later connection.

#### Scenario: Save valid VLESS link
- **WHEN** the user enters a syntactically valid supported VLESS link and confirms save
- **THEN** the system stores it as a saved connection configuration

### Requirement: System validates VLESS link input before saving
The system SHALL validate the VLESS link before persisting it and SHALL reject malformed or unsupported configurations with an explicit error.

#### Scenario: Reject malformed link
- **WHEN** the user submits a malformed VLESS link
- **THEN** the system refuses to save it and shows a validation error

#### Scenario: Reject unsupported parameters
- **WHEN** the user submits a syntactically valid VLESS link containing unsupported required parameters for v1
- **THEN** the system refuses to save it and identifies that the configuration is unsupported

### Requirement: Active VLESS configuration persists locally
The system SHALL persist saved VLESS links across application restarts and SHALL preserve selection state for the chosen saved VLESS configuration until the user changes or removes it.

#### Scenario: Relaunch app with saved configuration
- **WHEN** the application restarts after a VLESS link has been saved
- **THEN** the system restores the saved VLESS configuration list and the previously selected VLESS configuration when applicable
