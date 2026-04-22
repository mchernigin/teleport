## ADDED Requirements

### Requirement: Menu bar selection shows connection health context
The menu bar connection-selection flow SHALL expose compact server health information for saved manual and imported connections so the user can compare available options before connecting.

#### Scenario: Browse reachable options from the menu bar
- **WHEN** the user opens the connection picker and one or more saved connections have fresh successful health results
- **THEN** the picker shows compact reachability and latency context for those options

#### Scenario: Browse unreachable options from the menu bar
- **WHEN** the user opens the connection picker and one or more saved connections have fresh failed health results
- **THEN** the picker shows that those options are currently unreachable without removing them from selection

### Requirement: Menu bar supports health refresh for selection decisions
The menu bar UI SHALL provide a way to refresh visible server health information when the user wants current comparison data before connecting.

#### Scenario: Refresh health from the menu bar
- **WHEN** the user requests a health refresh from the menu bar UI
- **THEN** the system starts background probes for the relevant saved connections and updates the selection view as results arrive
