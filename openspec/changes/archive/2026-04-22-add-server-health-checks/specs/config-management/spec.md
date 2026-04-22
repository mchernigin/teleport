## ADDED Requirements

### Requirement: Saved connections retain health metadata
The system SHALL associate optional health metadata with each saved connection, including current health state, last-checked timestamp, measured latency when available, and the latest probe failure summary when unavailable.

#### Scenario: Save health metadata for a manual connection
- **WHEN** a health probe completes for a manually added saved connection
- **THEN** the system updates that saved connection's stored health metadata without changing unrelated connection fields

#### Scenario: Save health metadata for an imported connection
- **WHEN** a health probe completes for a subscription-imported saved connection
- **THEN** the system updates that saved connection's stored health metadata without removing its subscription source association
