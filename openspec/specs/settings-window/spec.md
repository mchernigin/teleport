# settings-window Specification

## Purpose
TBD - created by archiving change add-config-management. Update Purpose after archive.
## Requirements
### Requirement: Application provides a settings window
The application SHALL provide a dedicated settings window separate from the menu bar popover.

#### Scenario: Open settings from the menu bar
- **WHEN** the user invokes the Settings action from the menu bar UI
- **THEN** the application opens the settings window

### Requirement: Settings window includes a Connections tab
The settings window SHALL include a Connections tab for managing saved connection configs.

#### Scenario: User opens Connections settings
- **WHEN** the settings window is shown
- **THEN** the system displays a Connections tab with the saved connection list and connection-management actions

