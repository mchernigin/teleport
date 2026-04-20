## ADDED Requirements

### Requirement: User can enable the system proxy
The system SHALL allow the user to enable the macOS system proxy so traffic can be routed through the local proxy endpoint exposed by the bundled runtime.

#### Scenario: Enable proxy with runtime available
- **WHEN** the user enables the system proxy while a valid local proxy endpoint is available
- **THEN** the system applies the proxy settings needed for macOS to route traffic through the local endpoint

### Requirement: User can disable the system proxy
The system SHALL allow the user to disable proxy settings previously applied by the application.

#### Scenario: Disable proxy after it was enabled
- **WHEN** the user disables the system proxy
- **THEN** the system removes or deactivates the proxy settings managed by the application

### Requirement: Proxy changes are not applied without a usable local endpoint
The system SHALL prevent enabling the system proxy when the local proxy endpoint required by the runtime is unavailable.

#### Scenario: Prevent proxy enablement before runtime is ready
- **WHEN** the user attempts to enable the system proxy before the runtime has prepared a usable local endpoint
- **THEN** the system refuses the request and shows that the proxy cannot be enabled yet
