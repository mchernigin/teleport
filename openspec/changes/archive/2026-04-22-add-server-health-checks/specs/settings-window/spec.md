## ADDED Requirements

### Requirement: Connections settings show server health and latency
The Connections tab SHALL show health information for saved manual and imported connections, including whether each server is reachable and the latest measured latency when available.

#### Scenario: View reachable server health in Settings
- **WHEN** the user opens the Connections tab and a saved connection has a fresh successful health result
- **THEN** the row shows that the server is reachable together with its latest measured latency

#### Scenario: View failed server health in Settings
- **WHEN** the user opens the Connections tab and a saved connection has a fresh failed health result
- **THEN** the row shows that the server is unreachable together with a visible failure indication

### Requirement: Connections settings allow health refresh
The Connections tab SHALL provide a way to refresh server health information for saved manual and imported connections.

#### Scenario: Refresh health for a saved connection
- **WHEN** the user invokes a health refresh action for a saved connection from the Connections tab
- **THEN** the system starts a background probe for that connection and updates the row when the result is available

#### Scenario: Refresh health for a subscription group
- **WHEN** the user invokes a health refresh action for a saved subscription source
- **THEN** the system runs health probes for that source's imported connections without modifying their saved configuration data
