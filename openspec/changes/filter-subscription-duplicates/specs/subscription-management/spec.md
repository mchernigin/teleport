## ADDED Requirements

### Requirement: User can configure duplicate filtering for a subscription source
The system SHALL allow the user to configure whether duplicate imported configs are filtered for each subscription source, and the duplicate filter SHALL be enabled by default.

#### Scenario: New subscription defaults duplicate filtering to enabled
- **WHEN** the user adds a new subscription source
- **THEN** that source stores duplicate filtering as enabled unless the user later changes it

#### Scenario: User disables duplicate filtering for a subscription
- **WHEN** the user turns off duplicate filtering in a subscription source's settings and saves
- **THEN** the system preserves that preference for subsequent subscription refreshes

#### Scenario: Existing subscription without saved preference defaults to enabled
- **WHEN** the application restores a previously saved subscription source that has no stored duplicate-filter setting
- **THEN** the system treats duplicate filtering as enabled for that source

## MODIFIED Requirements

### Requirement: System imports supported configs from subscription contents
The system SHALL fetch subscription contents, parse supported connection links, and store each valid imported connection as a selectable saved connection associated with its subscription source. When duplicate filtering is enabled for that source, the system SHALL keep only one imported connection for each duplicate effective configuration and drop later duplicates from the same refresh result.

#### Scenario: Import valid unique entries from subscription
- **WHEN** a saved subscription source returns supported VLESS or Trojan links with distinct effective configurations
- **THEN** the system imports the valid supported entries and associates them with that subscription source

#### Scenario: Filter duplicate imported entries when enabled
- **WHEN** a saved subscription source returns multiple supported links that resolve to the same effective configuration and duplicate filtering is enabled for that source
- **THEN** the system imports only one of those duplicate entries for that refresh result

#### Scenario: Keep duplicate imported entries when filtering is disabled
- **WHEN** a saved subscription source returns multiple supported links that resolve to the same effective configuration and duplicate filtering is disabled for that source
- **THEN** the system imports all valid supported entries for that refresh result

#### Scenario: Skip unsupported entries during import
- **WHEN** a subscription payload contains malformed or unsupported links mixed with valid supported links
- **THEN** the system imports the valid supported links that remain after duplicate filtering and reports that some entries were skipped

### Requirement: System persists subscription sources and imported entries
The system SHALL persist saved subscription sources, their imported entries, source metadata, and duplicate-filter preference across app relaunches.

#### Scenario: Relaunch with saved subscription and duplicate-filter preference
- **WHEN** the application restarts after a subscription source has already been saved with a duplicate-filter preference
- **THEN** the system restores the subscription source, its duplicate-filter preference, and its imported entries from local state without requiring an immediate re-fetch

#### Scenario: Relaunch legacy subscription source without stored preference
- **WHEN** the application restarts with a saved subscription source from older persisted state that does not include the duplicate-filter preference
- **THEN** the system restores that source with duplicate filtering enabled by default
