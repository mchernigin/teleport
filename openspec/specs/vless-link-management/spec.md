# vless-link-management Specification

## Purpose
TBD - created by archiving change menubar-vless-client. Update Purpose after archive.
## Requirements
### Requirement: User can add a VLESS link
The system SHALL allow the user to input a VLESS share link and save it as the active connection configuration.

#### Scenario: Save valid VLESS link
- **WHEN** the user enters a syntactically valid supported VLESS link and confirms save
- **THEN** the system stores it as the active connection configuration

### Requirement: System validates VLESS link input before saving
The system SHALL validate the VLESS link before persisting it and SHALL reject malformed or unsupported configurations with an explicit error.

#### Scenario: Reject malformed link
- **WHEN** the user submits a malformed VLESS link
- **THEN** the system refuses to save it and shows a validation error

#### Scenario: Reject unsupported parameters
- **WHEN** the user submits a syntactically valid VLESS link containing unsupported required parameters for v1
- **THEN** the system refuses to save it and identifies that the configuration is unsupported

### Requirement: Active VLESS configuration persists locally
The system SHALL persist the active VLESS link across application restarts until the user replaces or clears it.

#### Scenario: Relaunch app with saved configuration
- **WHEN** the application restarts after a VLESS link has been saved
- **THEN** the system restores the saved VLESS configuration as the active connection

