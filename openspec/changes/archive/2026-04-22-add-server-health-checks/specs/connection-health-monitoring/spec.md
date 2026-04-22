## ADDED Requirements

### Requirement: System probes saved connection endpoints
The system SHALL probe each saved connection endpoint with a lightweight network check that determines whether the endpoint is currently reachable and, on success, measures probe latency.

#### Scenario: Probe succeeds for a saved connection
- **WHEN** the system runs a health check for a saved connection and the endpoint accepts the probe within the configured timeout
- **THEN** the system records the connection as reachable and stores the measured latency for that probe

#### Scenario: Probe fails for a saved connection
- **WHEN** the system runs a health check for a saved connection and the endpoint times out, refuses the connection, or otherwise cannot be reached
- **THEN** the system records the connection as unreachable and stores a failure summary for that probe result

### Requirement: System manages freshness and refresh of health results
The system SHALL distinguish fresh health results from stale or unknown results and SHALL support refreshing them without blocking normal connection management.

#### Scenario: User refreshes a stale or unknown result
- **WHEN** the user requests a health refresh for one or more saved connections
- **THEN** the system marks the affected connections as checking, runs background probes, and updates each result when its probe completes

#### Scenario: Stored result becomes stale
- **WHEN** the last successful or failed probe result for a saved connection ages past the freshness interval
- **THEN** the system stops treating that result as current and indicates that the connection requires a new health check

### Requirement: System restores recent health information across relaunch
The system SHALL persist the latest known health state, latency, and last-checked timestamp for each saved connection so the UI can restore recent health context after relaunch.

#### Scenario: Relaunch with prior health results
- **WHEN** the application launches after one or more saved connections were previously probed
- **THEN** the system restores the last known health metadata for those connections and applies freshness rules before presenting it as current
