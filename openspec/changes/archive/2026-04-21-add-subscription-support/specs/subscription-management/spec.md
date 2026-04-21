## ADDED Requirements

### Requirement: User can add a subscription source
The system SHALL allow the user to enter a supported subscription URL in the Connections settings and save it as a managed subscription source.

#### Scenario: Save valid subscription URL
- **WHEN** the user enters a valid subscription URL in the Connections settings and confirms add
- **THEN** the system stores the subscription source and begins an initial fetch for its contents

#### Scenario: Reject malformed subscription URL
- **WHEN** the user enters an invalid or unsupported subscription URL
- **THEN** the system refuses to save the source and shows a validation error

### Requirement: System imports supported configs from subscription contents
The system SHALL fetch subscription contents, parse supported connection links, and store each valid imported connection as a selectable saved connection associated with its subscription source.

#### Scenario: Import valid entries from subscription
- **WHEN** a saved subscription source returns supported VLESS or Trojan links
- **THEN** the system imports the valid entries and associates them with that subscription source

#### Scenario: Skip unsupported entries during import
- **WHEN** a subscription payload contains malformed or unsupported links mixed with valid supported links
- **THEN** the system imports the valid supported entries and reports that some entries were skipped

### Requirement: System refreshes subscription-managed entries atomically
The system SHALL replace the previously imported entries for a subscription source with the latest successfully parsed result from that same source as one logical update.

#### Scenario: Refresh replaces prior imported entries
- **WHEN** the user refreshes a subscription source and the fetch succeeds
- **THEN** the system replaces that source's previously imported entries with the new imported entries without affecting manual saved connections or entries from other sources

#### Scenario: Failed refresh preserves last imported entries
- **WHEN** a subscription refresh fails due to network or parsing errors
- **THEN** the system keeps the previously imported entries for that source and shows the refresh error

### Requirement: System persists subscription sources and imported entries
The system SHALL persist saved subscription sources, their imported entries, and source metadata across app relaunches.

#### Scenario: Relaunch with saved subscription
- **WHEN** the application restarts after a subscription source has already imported entries
- **THEN** the system restores the subscription source and its imported entries from local state without requiring an immediate re-fetch
