## ADDED Requirements

### Requirement: User can manage multiple saved connection configs
The system SHALL allow the user to maintain multiple saved connection configs spanning supported protocols and SHALL persist them as independent saved entries.

#### Scenario: Add a new supported connection config
- **WHEN** the user submits a valid supported connection link in the Connections settings tab
- **THEN** the system saves it as a new connection entry without removing existing saved entries

#### Scenario: Remove a saved connection config
- **WHEN** the user removes a saved connection from the Connections settings tab
- **THEN** the system deletes only that saved entry and preserves all other saved connections

### Requirement: System tracks a selected saved connection config
The system SHALL maintain a selected saved connection config that is used for connection actions and restored across app launches.

#### Scenario: Select a saved connection
- **WHEN** the user chooses one of the saved connection configs
- **THEN** the system marks that config as selected and uses it as the active target for future connection actions

#### Scenario: Restore selected connection on relaunch
- **WHEN** the application relaunches after the user previously selected a saved connection
- **THEN** the system restores the same selected connection if it still exists

### Requirement: Existing single-config state migrates to the multi-config model
The system SHALL migrate legacy single-config persisted state into the multi-config model automatically.

#### Scenario: Relaunch with legacy saved state
- **WHEN** the application starts with persisted state from the single-config version
- **THEN** the system creates one saved connection entry from the legacy data and selects it automatically
