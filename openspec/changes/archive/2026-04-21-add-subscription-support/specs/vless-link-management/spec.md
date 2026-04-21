## MODIFIED Requirements

### Requirement: User can add a VLESS link
The system SHALL allow the user to input a VLESS share link and save it as a saved connection configuration that can coexist with other saved connections. The user SHALL be able to select that saved VLESS configuration for later connection, whether it was entered manually or imported from a subscription source.

#### Scenario: Save valid VLESS link
- **WHEN** the user enters a syntactically valid supported VLESS link and confirms save
- **THEN** the system stores it as a saved connection configuration

#### Scenario: Import valid VLESS link from subscription
- **WHEN** a subscription source contains a syntactically valid supported VLESS link
- **THEN** the system stores it as an imported saved connection configuration

### Requirement: System validates VLESS link input before saving
The system SHALL validate the VLESS link before persisting it and SHALL reject malformed or unsupported configurations with an explicit error.

#### Scenario: Reject malformed link
- **WHEN** the user submits a malformed VLESS link
- **THEN** the system refuses to save it and shows a validation error

#### Scenario: Reject unsupported parameters
- **WHEN** the user submits a syntactically valid VLESS link containing unsupported required parameters for v1
- **THEN** the system refuses to save it and identifies that the configuration is unsupported

#### Scenario: Skip malformed VLESS link in subscription payload
- **WHEN** a subscription payload contains a malformed or unsupported VLESS link
- **THEN** the system skips importing that VLESS link and records the import failure without aborting valid sibling imports

### Requirement: Active VLESS configuration persists locally
The system SHALL persist saved VLESS links across application restarts and SHALL preserve selection state for the chosen saved VLESS configuration until the user changes or removes it.

#### Scenario: Relaunch app with saved configuration
- **WHEN** the application restarts after a VLESS link has been saved
- **THEN** the system restores the saved VLESS configuration list and the previously selected VLESS configuration when applicable

#### Scenario: Relaunch app with imported VLESS configuration
- **WHEN** the application restarts after a subscription source has imported VLESS configurations
- **THEN** the system restores the imported VLESS configurations from persisted state
