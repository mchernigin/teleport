## MODIFIED Requirements

### Requirement: User can add a Trojan link
The system SHALL allow the user to input a supported Trojan share link and save it as a saved connection configuration that can coexist with other saved connections. The user SHALL be able to select that saved Trojan configuration for later connection, whether it was entered manually or imported from a subscription source.

#### Scenario: Save valid Trojan TLS link
- **WHEN** the user enters a syntactically valid supported Trojan TLS link and confirms save
- **THEN** the system stores it as a saved connection configuration

#### Scenario: Save valid Trojan Reality link
- **WHEN** the user enters a syntactically valid supported Trojan Reality link and confirms save
- **THEN** the system stores it as a saved connection configuration

#### Scenario: Import valid Trojan link from subscription
- **WHEN** a subscription source contains a syntactically valid supported Trojan link
- **THEN** the system stores it as an imported saved connection configuration

### Requirement: System validates Trojan link input before saving
The system SHALL validate Trojan links before persisting them and SHALL reject malformed or unsupported Trojan configurations with an explicit error, including missing Reality-specific metadata when Reality is requested.

#### Scenario: Reject malformed Trojan link
- **WHEN** the user submits a malformed Trojan link
- **THEN** the system refuses to save it and shows a validation error

#### Scenario: Reject unsupported Trojan parameters
- **WHEN** the user submits a syntactically valid supported Trojan link containing unsupported required parameters for the current release
- **THEN** the system refuses to save it and identifies that the Trojan configuration is unsupported

#### Scenario: Reject Trojan Reality link missing required parameters
- **WHEN** the user submits a Trojan Reality link missing required Reality parameters such as public key or server name
- **THEN** the system refuses to save it and identifies the missing parameter

#### Scenario: Skip malformed Trojan link in subscription payload
- **WHEN** a subscription payload contains a malformed or unsupported Trojan link
- **THEN** the system skips importing that Trojan link and records the import failure without aborting valid sibling imports

### Requirement: Active Trojan configuration persists locally
The system SHALL persist saved Trojan links across application restarts and SHALL preserve selection state for the chosen saved Trojan configuration until the user changes or removes it.

#### Scenario: Relaunch app with saved Trojan configuration
- **WHEN** the application restarts after a Trojan link has been saved
- **THEN** the system restores the saved Trojan configuration list and the previously selected Trojan configuration when applicable

#### Scenario: Relaunch app with imported Trojan configuration
- **WHEN** the application restarts after a subscription source has imported Trojan configurations
- **THEN** the system restores the imported Trojan configurations from persisted state
