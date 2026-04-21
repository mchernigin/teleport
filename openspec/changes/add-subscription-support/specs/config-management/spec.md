## MODIFIED Requirements

### Requirement: User can manage multiple saved connection configs
The system SHALL allow the user to maintain multiple saved connection configs spanning supported protocols and SHALL persist them as independent saved entries, including entries imported from subscription sources.

#### Scenario: Add a new supported connection config
- **WHEN** the user submits a valid supported connection link in the Connections settings tab
- **THEN** the system saves it as a new connection entry without removing existing saved entries

#### Scenario: Remove a saved connection config
- **WHEN** the user removes a saved connection from the Connections settings tab
- **THEN** the system deletes only that saved entry and preserves all other saved connections

#### Scenario: Import subscription-derived connection configs
- **WHEN** the system successfully parses supported connection links from a saved subscription source
- **THEN** the system stores them as saved connection entries while preserving unrelated manual entries

### Requirement: System tracks a selected saved connection config
The system SHALL maintain a selected saved connection config that is used for connection actions and restored across app launches, whether the selected entry was added manually or imported from a subscription source.

#### Scenario: Select a saved connection
- **WHEN** the user chooses one of the saved connection configs
- **THEN** the system marks that config as selected and uses it as the active target for future connection actions

#### Scenario: Restore selected connection on relaunch
- **WHEN** the application relaunches after the user previously selected a saved connection
- **THEN** the system restores the same selected connection if it still exists

#### Scenario: Preserve selection across subscription refresh
- **WHEN** the selected saved connection was imported from a subscription source and that source refreshes successfully
- **THEN** the system preserves the selection if an equivalent imported connection still exists in the refreshed result

### Requirement: Existing single-config state migrates to the multi-config model
The system SHALL migrate legacy single-config persisted state into the multi-config model automatically and SHALL preserve manual connections when expanding the persisted model to support subscriptions.

#### Scenario: Relaunch with legacy saved state
- **WHEN** the application starts with persisted state from the single-config version
- **THEN** the system creates one saved connection entry from the legacy data and selects it automatically

#### Scenario: Relaunch with pre-subscription multi-config state
- **WHEN** the application starts with persisted state created before subscription support was added
- **THEN** the system loads the existing manual saved connections without requiring subscription metadata to be present
